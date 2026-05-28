class GuideMarkdownRenderer
  Result = Struct.new(:html, :outline, keyword_init: true) do
    def to_s = html.to_s
  end

  class Error < StandardError; end

  MAX_SHORTCODE_PASSES = 200
  MAX_RECURSION_DEPTH  = 4

  BLOCK_SHORTCODE_RE = /^:::(?<name>[a-z][a-z0-9_-]*)(?<attrs>(?:[ \t]+[a-z][a-z0-9_-]*=(?:"[^"\n]*"|[^\s"]+))*)[ \t]*\n(?<content>(?:(?!^:::).)*)^:::[ \t]*(?=\n|\z)/m
  INLINE_SHORTCODE_RE = /::(?<name>[a-z][a-z0-9_-]*)\[(?<content>[^\[\]\n]*)\]/x
  ATTR_RE             = /([a-z][a-z0-9_-]*)=("[^"]*"|\S+)/
  BLOCK_MARKER_RE     = /\[\[GUIDE_BLOCK:(\d+)\]\]/
  INLINE_MARKER_RE    = /\[\[GUIDE_INLINE:(\d+)\]\]/
  CODE_MARKER_RE      = /\A\[\[GUIDE_CODE:(\d+)\]\]\z/

  CALLOUT_TYPES     = %w[info tip warning danger].freeze
  BLOCK_SHORTCODES  = %w[callout collapse].freeze
  INLINE_SHORTCODES = %w[kbd mark].freeze

  def self.render(text)
    new(text).call
  end

  def initialize(text)
    @text = text.to_s
    @block_registry  = []
    @inline_registry = []
    @code_registry   = []
  end

  def call
    extracted = extract_blocks(@text)
    text_with_markers = extract_inlines_in_place(extracted)
    @block_registry.each_with_index do |entry, i|
      @block_registry[i] = entry.merge(content: extract_inlines_in_place(entry[:content]))
    end

    outline = build_outline(text_with_markers)
    html    = render_pipeline(text_with_markers, depth: 0)
    Result.new(html: html, outline: outline)
  end

  private

  def extract_blocks(text)
    pass = 0
    loop do
      pass += 1
      raise Error, "too many shortcode passes" if pass > MAX_SHORTCODE_PASSES

      match = text.match(BLOCK_SHORTCODE_RE)
      break text unless match

      name  = match[:name]
      attrs = parse_attrs(match[:attrs])

      unless BLOCK_SHORTCODES.include?(name)
        text = text.sub(match[0], "")
        next
      end

      id = @block_registry.size
      @block_registry << { name: name, attrs: attrs, content: match[:content] }
      text = text.sub(match[0], "\n\n[[GUIDE_BLOCK:#{id}]]\n\n")
    end
    text
  end

  def extract_inlines_in_place(text)
    text.gsub(INLINE_SHORTCODE_RE) do
      name    = Regexp.last_match[:name]
      content = Regexp.last_match[:content]
      if INLINE_SHORTCODES.include?(name)
        id = @inline_registry.size
        @inline_registry << { name: name, content: content }
        "[[GUIDE_INLINE:#{id}]]"
      else
        ""
      end
    end
  end

  def parse_attrs(str)
    attrs = {}
    str.to_s.scan(ATTR_RE) do |key, value|
      value = value[1..-2] if value.start_with?('"') && value.end_with?('"')
      attrs[key] = value
    end
    attrs
  end

  # Builds a slug assigner that tracks collisions: the second "Setup" heading
  # becomes "section-setup-2", not a duplicate of the first. build_outline and
  # section_by_h2 each construct their own assigner and walk headings in
  # document order so the slugs line up.
  def slug_assigner
    seen = Hash.new(0)
    ->(heading_text) {
      base = heading_text.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      base = "section" if base.empty?
      suffix = seen[base].zero? ? "" : "-#{seen[base] + 1}"
      seen[base] += 1
      "section-#{base}#{suffix}"
    }
  end

  def build_outline(text)
    assign = slug_assigner
    outline = []
    text.scan(/^##[ \t]+(.+?)[ \t]*$/) do |(heading_text)|
      cleaned = heading_text.gsub(/[*_`]/, "").strip
      next if cleaned.empty?
      outline << { index: outline.size, text: cleaned, id: assign.call(cleaned) }
    end
    outline.freeze
  end

  def render_pipeline(text, depth:)
    raise Error, "guide markdown recursion too deep" if depth > MAX_RECURSION_DEPTH

    raw_html = Commonmarker.to_html(
      text,
      options: {
        parse: { smart: true },
        extension: {
          strikethrough: true,
          underline: true,
          table: true,
          autolink: true,
          tagfilter: true
        }
      },
    )

    # Extract language-tagged code blocks BEFORE sanitize — class="language-X"
    # gets stripped by the sanitizer, so we'd otherwise lose the language hint.
    # The marker survives sanitize as plain text inside <pre>, and we expand
    # it back to rouge-highlighted HTML after the rest of the pipeline runs.
    raw_html = extract_code_blocks(raw_html)

    sanitized = MarkdownRenderer.sanitize_html(
      raw_html,
      extra_tags:       %w[u kbd mark table thead tbody tfoot tr th td],
      extra_attributes: %w[target rel id]
    )

    doc = Nokogiri::HTML5.fragment(sanitized)
    expand_blocks(doc, depth: depth)
    expand_inlines(doc)
    expand_code_blocks(doc)
    section_by_h2(doc) if depth.zero?
    post_process(doc)
    doc.to_html
  end

  def extract_code_blocks(html)
    doc = Nokogiri::HTML5.fragment(html)
    # Commonmarker 2.x emits language-tagged code blocks as `<pre lang="X">`
    # with its own inline-styled token spans inside. We want our rouge output
    # instead, so swap the whole block for a placeholder. The pre's text
    # content concatenates the spans and gives us the original source back.
    doc.css("pre[lang]").each do |pre_node|
      language = pre_node["lang"].to_s.strip
      next if language.empty?

      code_text = pre_node.text
      id = @code_registry.size
      @code_registry << { language: language, code: code_text }

      placeholder = Nokogiri::XML::Node.new("pre", doc.document)
      placeholder.content = "[[GUIDE_CODE:#{id}]]"
      pre_node.replace(placeholder)
    end
    doc.to_html
  end

  def expand_code_blocks(doc)
    doc.css("pre").each do |pre|
      match = pre.text.strip.match(CODE_MARKER_RE)
      next unless match

      entry = @code_registry[match[1].to_i]
      next unless entry

      pre.replace(Nokogiri::HTML5.fragment(render_code_block(entry)))
    end
  end

  # Renders a fenced code block with Rouge syntax highlighting. Falls back to
  # plain text when the language isn't recognized (Rouge ships hundreds, but
  # authors can still type something obscure).
  def render_code_block(entry)
    lexer = Rouge::Lexer.find(entry[:language])&.new || Rouge::Lexers::PlainText.new
    formatter = Rouge::Formatters::HTML.new
    highlighted = formatter.format(lexer.lex(entry[:code]))
    language_class = lexer.tag
    %(<pre class="guide-code"><code class="language-#{language_class}">#{highlighted}</code></pre>)
  end

  # Collect-then-apply: mutating the DOM while doc.traverse walks it can
  # invalidate libxml2's cursor. Build the full work list first, then apply
  # the replacements once the walk is done.
  def expand_blocks(doc, depth:)
    replacements = []
    doc.traverse do |node|
      next unless node.text?
      next unless node.content =~ BLOCK_MARKER_RE

      parent = node.parent
      if parent && parent.name == "p" && parent.content.strip =~ /\A\[\[GUIDE_BLOCK:\d+\]\]\z/
        id = parent.content.strip[/\d+/].to_i
        replacement_html = render_block_shortcode(@block_registry[id], depth: depth + 1)
        replacements << [ parent, replacement_html ]
      else
        new_content = node.content.gsub(BLOCK_MARKER_RE) do
          id = Regexp.last_match(1).to_i
          render_block_shortcode(@block_registry[id], depth: depth + 1)
        end
        replacements << [ node, new_content ]
      end
    end

    replacements.each do |target, html|
      target.replace(Nokogiri::HTML5.fragment(html))
    end
  end

  def expand_inlines(doc)
    replacements = []
    doc.traverse do |node|
      next unless node.text?
      next unless node.content =~ INLINE_MARKER_RE

      new_content = node.content.gsub(INLINE_MARKER_RE) do
        id = Regexp.last_match(1).to_i
        render_inline_shortcode(@inline_registry[id])
      end
      replacements << [ node, new_content ]
    end

    replacements.each do |target, html|
      target.replace(Nokogiri::HTML5.fragment(html))
    end
  end

  def section_by_h2(doc)
    children = doc.children.to_a
    return if children.empty?

    assign = slug_assigner
    sections = []
    current  = []
    section_index = -1

    children.each do |child|
      if child.element? && child.name == "h2"
        sections << { index: section_index, nodes: current } if section_index >= 0 || current.any?
        section_index += 1
        h2_text = child.text.strip
        child["id"] = assign.call(h2_text) if h2_text.present?
        current = [ child ]
      else
        current << child
      end
    end
    sections << { index: section_index, nodes: current } if current.any?

    children.each(&:unlink)

    sections.each do |section|
      if section[:index] < 0
        section[:nodes].each { |n| doc.add_child(n) }
      else
        section_node = Nokogiri::XML::Node.new("section", doc.document)
        section_node["class"] = "guide-section"
        section_node["data-section-index"] = section[:index].to_s
        section[:nodes].each { |n| section_node.add_child(n) }
        doc.add_child(section_node)
      end
    end
  end

  def post_process(doc)
    MarkdownRenderer.harden_links_and_images(doc)
  end

  def render_block_shortcode(entry, depth:)
    case entry[:name]
    when "callout"    then render_callout(entry, depth: depth)
    when "collapse"   then render_collapse(entry, depth: depth)
    else ""
    end
  end

  def render_inline_shortcode(entry)
    content = ERB::Util.html_escape(entry[:content].to_s)
    case entry[:name]
    when "kbd"  then %(<kbd class="guide-kbd">#{content}</kbd>)
    when "mark" then %(<mark class="guide-mark">#{content}</mark>)
    else content
    end
  end

  def render_callout(entry, depth:)
    type = entry[:attrs]["type"].to_s
    type = "info" unless CALLOUT_TYPES.include?(type)
    title_attr = entry[:attrs]["title"].to_s
    title_html = title_attr.empty? ? "" : %(<p class="guide-callout__title">#{ERB::Util.html_escape(title_attr)}</p>)
    inner_html = render_pipeline(entry[:content], depth: depth)
    <<~HTML
      <aside class="guide-callout guide-callout--#{type}" role="note">
        #{title_html}
        <div class="guide-callout__body">#{inner_html}</div>
      </aside>
    HTML
  end

  def render_collapse(entry, depth:)
    summary = entry[:attrs]["summary"].to_s
    summary = "Details" if summary.empty?
    summary_html = ERB::Util.html_escape(summary)
    inner_html = render_pipeline(entry[:content], depth: depth)
    <<~HTML
      <details class="guide-collapse">
        <summary class="guide-collapse__summary">#{summary_html}</summary>
        <div class="guide-collapse__body">#{inner_html}</div>
      </details>
    HTML
  end
end
