# frozen_string_literal: true

class StarBorderComponent < ViewComponent::Base
  VARIANTS = (1..5).to_a.freeze

  attr_reader :variant, :compact, :html_options

  # variant: 1..5, pinned. Random if nil.
  # seed:    stable hash → variant. Ignored if `variant:` is set.
  # compact: true forces the single-line SVG, false forces the tall (square) SVG.
  #          nil (default) lets CSS auto-pick: compact if the slot contains a
  #          non-file <input> and no <textarea>, otherwise tall.
  def initialize(variant: nil, seed: nil, compact: nil, **html_options)
    @variant = resolve_variant(variant, seed)
    @compact = compact
    @html_options = html_options
  end

  def root_classes
    class_names(
      "star-border",
      "star-border--variant-#{variant}",
      { "star-border--compact" => compact == true },
      { "star-border--tall" => compact == false },
      html_options[:class]
    )
  end

  def root_attributes
    html_options.except(:class).merge(class: root_classes)
  end

  private

  def resolve_variant(variant, seed)
    if variant
      v = variant.to_i
      return v if VARIANTS.include?(v)
      raise ArgumentError, "variant must be one of #{VARIANTS.inspect}, got #{variant.inspect}"
    end

    return (seed.to_s.hash.abs % VARIANTS.size) + VARIANTS.first if seed

    VARIANTS.sample
  end
end
