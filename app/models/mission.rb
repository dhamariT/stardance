# == Schema Information
#
# Table name: missions
#
#  id                           :bigint           not null, primary key
#  achievement_description      :text
#  achievement_name             :string
#  default_project_description  :text
#  default_project_title        :string
#  deleted_at                   :datetime
#  description                  :text             not null
#  difficulty                   :string
#  enabled                      :boolean          default(TRUE), not null
#  end_at                       :datetime
#  estimated_completion_minutes :integer
#  featured_at                  :datetime
#  name                         :string           not null
#  prizes_count                 :integer          default(0), not null
#  slug                         :string           not null
#  start_at                     :datetime
#  steps_count                  :integer          default(0), not null
#  submission_guide             :text
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_missions_on_deleted_at   (deleted_at)
#  index_missions_on_enabled      (enabled)
#  index_missions_on_featured_at  (featured_at)
#  index_missions_on_slug         (slug) UNIQUE
#
class Mission < ApplicationRecord
  include SoftDeletable

  has_paper_trail

  has_one_attached :icon
  has_one_attached :banner

  has_many :steps, class_name: "Mission::Step", dependent: :destroy
  has_many :prizes, class_name: "Mission::Prize", dependent: :destroy
  has_many :memberships, class_name: "Mission::Membership", dependent: :destroy
  has_many :shop_unlocks, class_name: "Mission::ShopUnlock", dependent: :destroy
  has_many :submissions, class_name: "Mission::Submission", dependent: :destroy
  has_many :attachments, class_name: "Project::MissionAttachment", dependent: :destroy
  has_many :projects, through: :attachments
  has_many :guide_variants, -> { order(:position, :id) },
           class_name: "Mission::GuideVariant", dependent: :destroy, inverse_of: :mission
  has_many :section_completions, class_name: "Mission::SectionCompletion", dependent: :destroy

  accepts_nested_attributes_for :guide_variants, allow_destroy: true,
                                                 reject_if: ->(attrs) { attrs[:language].blank? && attrs[:body].blank? }

  has_many :owners,    -> { where(mission_memberships: { role: :owner }) },
           through: :memberships, source: :user
  has_many :reviewers, -> { where(mission_memberships: { role: :reviewer }) },
           through: :memberships, source: :user

  DIFFICULTIES = %w[beginner intermediate advanced].freeze
  enum :difficulty, DIFFICULTIES.index_with(&:itself), prefix: true

  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9_-]*\z/, message: "must be URL-safe" }
  validates :name, presence: true
  validates :description, presence: true
  validates :estimated_completion_minutes,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100_000 },
            allow_nil: true
  validates :default_project_title, length: { maximum: 120 }, allow_blank: true
  validates :default_project_description, length: { maximum: 1_000 }, allow_blank: true

  scope :enabled,  -> { where(enabled: true) }
  scope :featured, -> { where.not(featured_at: nil) }

  scope :available, -> {
    enabled
      .where("start_at IS NULL OR start_at <= ?", Time.current)
      .where("end_at   IS NULL OR end_at   > ?", Time.current)
  }

  def started? = start_at.nil? || start_at <= Time.current
  def ended?   = end_at.present? && end_at <= Time.current
  def coming_soon? = !started?

  def available_to_builders?
    enabled? && started? && !ended?
  end

  def has_steps?  = steps.any?
  def has_prizes? = prizes.any?

  # Per-mission achievement slug. Nil when no achievement is configured (admin
  # left achievement_name blank).
  def achievement_slug
    return nil if achievement_name.blank?
    "mission_#{slug}_completed"
  end

  # Every guide is a Mission::GuideVariant (after the unification migration
  # 20260526201529). The variant at the lowest position is the "default" tab
  # — what the public mission page links to and what shows when no language
  # is selected. Steps are an alternate authoring surface for that variant's
  # body markdown; the variant's after_save callback keeps the two in sync.

  def default_guide
    guide_variants.order(:position, :id).first
  end

  def has_guide? = guide_variants.any?

  # All languages this mission's guide is authored in, in tab order.
  def available_languages
    guide_variants.order(:position, :id).pluck(:language)
  end

  def has_multiple_guide_languages? = available_languages.length > 1

  def primary_guide_language_label
    default_guide&.language.presence || "Guide"
  end

  # Resolve a user-facing language string to a canonical variant language.
  # Blank → the default variant's language (or nil if no guides yet). A
  # known variant → its canonical casing. An unknown non-blank label → the
  # literal string (so the first step-add or paste for that name creates the
  # variant).
  def resolve_storage_language(requested)
    label = requested.to_s.strip
    return default_guide&.language if label.blank?
    existing = guide_variants.find_by("LOWER(language) = ?", label.downcase)&.language
    existing || label
  end

  # The markdown body for a given language. Falls back to the default
  # variant's body when the requested language doesn't exist.
  def guide_body_for(language)
    return nil if language.blank?
    variant = guide_variants.find_by("LOWER(language) = ?", language.to_s.downcase)
    variant&.body || default_guide&.body
  end

  # The outline / section list comes from the shared `Mission::Step` table.
  # The slug for each section is `step-#{step.id}` — stable across every
  # language since the step row is shared. Mission::SectionCompletion keys
  # on mission_step_id, so a builder who ticks "Setup" in the JS guide sees
  # it ticked in the Python guide too.
  def guide_sections
    steps.where(deleted_at: nil).ordered.map.with_index do |step, idx|
      { index: idx, id: "step-#{step.id}", text: step.title, mission_step_id: step.id }
    end
  end

  # The default guide's last-edited timestamp. Drives the "updated N days ago"
  # badge on the mission home.
  def guide_body_updated_at = default_guide&.body_updated_at

  # Any non-blank content before the first `## H2` heading in a pasted body.
  # `parse_h2_sections` discards pre-heading lines (steps own the structure),
  # so the controller surfaces this to the author instead of silently losing
  # their intro paragraph.
  def self.guide_paste_preamble(text)
    preamble = []
    text.to_s.split(/\r?\n/).each do |line|
      break if line.match?(/\A##\s+/)
      preamble << line
    end
    preamble.join("\n").strip.presence
  end

  # Parse the H2 sections of a markdown body. Used both for importing a
  # variant's body into Mission::Step rows and for the public-facing outline
  # (via MarkdownRenderer).
  def self.parse_h2_sections(text)
    return [] if text.to_s.strip.empty?
    sections = []
    current = nil
    # Split on either Unix or Windows line endings so CRLF-pasted guides
    # (Windows, some Slack/Notion exports) don't leave \r at end of lines.
    text.split(/\r?\n/).each do |line|
      if (m = line.match(/\A##\s+(.*)\z/))
        sections << current if current
        current = { title: m[1].strip, body: [] }
      elsif current
        current[:body] << line
      end
    end
    sections << current if current
    sections.map { |s| { title: s[:title], body: s[:body].join("\n").strip } }
  end

  # Demote heading levels inside a step's body so the topmost heading lands at
  # H3 (the step title is H2, so its body's headings start one level below).
  # Preserves the relative hierarchy: if the body has both H1 and H2, the H1
  # becomes H3 and the H2 becomes H4.
  def self.shift_headings_for_step(body)
    return body.to_s if body.to_s.strip.empty?
    lines = body.split("\n")
    levels = lines.filter_map { |l| l.match(/\A(#+)\s+/)&.captures&.first&.length }
    return body if levels.empty?
    shift = 3 - levels.min
    return body if shift <= 0
    lines.map { |l|
      if (m = l.match(/\A(#+)(\s+.*)\z/))
        new_level = [ [ m[1].length + shift, 1 ].max, 6 ].min
        "#{'#' * new_level}#{m[2]}"
      else
        l
      end
    }.join("\n")
  end

  # All languages this mission's guide is authored in: the primary language
  # Rebuild a variant's body from the shared steps + their per-language
  # StepBody rows. Steps with no body for the requested language render with
  # an empty section body (the step title still appears as the H2). Called
  # after step CRUD on a given language tab.
  def regenerate_text_for_language!(language)
    return if language.blank?

    ordered = steps.where(deleted_at: nil).ordered.to_a
    new_body = ordered.map { |step|
      title = step.title.to_s.strip
      raw   = step.body_for(language).to_s.strip
      body  = Mission.shift_headings_for_step(raw)
      body.present? ? "## #{title}\n\n#{body}" : "## #{title}"
    }.join("\n\n").strip

    save_variant_atomically(language, new_body)
  end

  # Wraps the variant save in a single retry on RecordNotUnique so two
  # concurrent first-paste requests for the same brand-new language don't
  # collide on the (mission_id, language) unique index.
  def save_variant_atomically(language, new_body, retried: false)
    variant = guide_variants
                .where("LOWER(language) = ?", language.to_s.downcase)
                .first || guide_variants.new(
                  language: language,
                  position: (guide_variants.maximum(:position).to_i + 1)
                )
    variant._skip_steps_sync = true
    variant.body = new_body
    variant.save!
  rescue ActiveRecord::RecordNotUnique
    raise if retried
    save_variant_atomically(language, new_body, retried: true)
  end
  private :save_variant_atomically

  # Reconcile the shared-step structure + this language's bodies against the
  # H2 sections in the variant's body. Used by the variant's after_save
  # callback when a paste-modal submission lands.
  #
  # Steps are unified across languages: pasting a guide is the source of
  # truth for step COUNT and order as well as bodies. If the parse has more
  # sections than existing shared steps, new steps are created. If it has
  # FEWER, the extras are soft-deleted (which affects every language — the
  # paste-modal explicitly warns that submitting overwrites). Authors who
  # want to edit just one section should use the per-step UI instead.
  def sync_steps_for_language!(language)
    return if language.blank?
    variant = guide_variants.find_by("LOWER(language) = ?", language.to_s.downcase)
    canonical = variant&.language || language.to_s
    parsed = Mission.parse_h2_sections(variant&.body.to_s)
    structure_changed = false

    Mission::Step.transaction do
      shared = steps.where(deleted_at: nil).ordered.to_a
      parsed.each_with_index do |section, idx|
        step = shared[idx]
        title = section[:title].presence || "Untitled step"
        body  = section[:body].presence || ""

        if step
          # Update the title only if it changed (the title is shared across
          # all languages so editing it propagates).
          step.update!(title: title) if step.title != title
        else
          step = steps.create!(title: title, position: idx + 1)
          structure_changed = true
        end
        step.upsert_body_for!(canonical, body)
      end

      # Soft-delete shared steps the paste no longer covers — affects every
      # language since steps are shared.
      extras = shared.drop(parsed.length)
      extras.each do |extra|
        extra.update!(deleted_at: Time.current)
      end
      structure_changed ||= extras.any?
    end

    # Step structure changed (added or removed) → other languages' stored
    # variant.body is now out of sync with the shared step list. Rebuild
    # their bodies from the current step structure so e.g. the manage edit
    # preview tab reflects reality without waiting for a per-tab edit.
    if structure_changed
      guide_variants.where.not("LOWER(language) = ?", canonical.downcase).each do |sibling|
        regenerate_text_for_language!(sibling.language)
      end
    end
  end

  # The submission_guide markdown is authored as: an intro paragraph, then a
  # bulleted list of reviewer criteria, then an optional outro paragraph. The
  # D6 mission home renders each piece independently (intro + numbered cards +
  # outro). These helpers do that split with simple line-by-line parsing — no
  # markdown AST needed since we only care about top-level dash bullets.
  def submission_guide_lines
    submission_guide.to_s.split(/\r?\n/)
  end

  def submission_criteria
    submission_guide_lines.filter_map do |line|
      stripped = line.strip
      next unless stripped.start_with?("- ", "* ")
      stripped.sub(/^[\-\*]\s+/, "").presence
    end
  end

  def submission_guide_intro
    return nil if submission_guide.blank?
    lines = submission_guide_lines.take_while { |l| !l.strip.start_with?("- ", "* ") }
    lines.join("\n").strip.presence
  end

  def submission_guide_outro
    return nil if submission_guide.blank?
    lines = submission_guide_lines
    first_bullet = lines.find_index { |l| l.strip.start_with?("- ", "* ") }
    return nil unless first_bullet
    after = lines[first_bullet..].drop_while { |l| l.strip.start_with?("- ", "* ") || l.strip.empty? }
    after.join("\n").strip.presence
  end

  # Friendly mission ID for the curved patch text + crumb suffix. Derived from
  # the slug — keeps things consistent without an extra column.
  def display_id
    "STR-#{(id.to_i % 1000).to_s.rjust(3, "0")}"
  end

  # Pretty estimated-time label for the home page chip. Returns nil when
  # estimated_completion_minutes is not set.
  def estimated_completion_label
    return nil if estimated_completion_minutes.blank?
    mins = estimated_completion_minutes.to_i
    return nil if mins <= 0
    if mins < 60
      "~#{mins} min"
    else
      hours, remainder = mins.divmod(60)
      if remainder.zero?
        "~#{hours} hr"
      else
        "~#{hours} hr #{remainder} min"
      end
    end
  end

  # Rotating gallery for the mission home. Ranks by total ship votes, ties
  # broken by newest project id.
  def showcase_projects(limit: 6)
    devlog_likes = Post::Devlog
                     .joins(:post)
                     .group("posts.project_id")
                     .select("posts.project_id, SUM(post_devlogs.likes_count) AS devlog_likes_count")

    Project
      .joins(:mission_attachments)
      .where(project_mission_attachments: { mission_id: id, detached_at: nil }, deleted_at: nil)
      .joins("LEFT JOIN (#{devlog_likes.to_sql}) mission_devlog_likes ON mission_devlog_likes.project_id = projects.id")
      .left_joins(:project_follows)
      .group("projects.id", "mission_devlog_likes.devlog_likes_count")
      .order(Arel.sql(<<~SQL))
        (COALESCE(mission_devlog_likes.devlog_likes_count, 0)
          + COUNT(DISTINCT project_follows.id)) DESC,
        projects.id DESC
      SQL
      .limit(limit)
      .includes(:users)
      .with_attached_banner
      .to_a
  end

  def approved_submission_project_ids
    submissions
      .where(status: "approved")
      .joins(ship_event: :post)
      .distinct
      .pluck("posts.project_id")
  end
end
