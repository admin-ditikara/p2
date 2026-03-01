class Status < ApplicationRecord
  TITLE = Setting.find_by_name("statuses_title")&.value || "Status" rescue "Status"

  include ModelLibrary

  # Associations — models migrate progressively; associations activate once their tables exist
  has_many :addresses
  has_many :attachments
  has_many :categories
  has_many :employees
  has_many :fields
  has_many :helps
  has_many :lookups
  has_many :navigs
  has_many :plans
  has_many :os_plans,     class_name: "Plan",    foreign_key: :os_id
  has_many :steps
  has_many :os_steps,     class_name: "Step",    foreign_key: :os_id
  has_many :run_plans
  has_many :os_run_plans, class_name: "RunPlan", foreign_key: :os_id
  has_many :wrs
  has_many :os_wrs,       class_name: "Wr",      foreign_key: :os_id
  has_many :wos
  has_many :os_wos,       class_name: "Wo",      foreign_key: :os_id
  has_many :tasks
  has_many :os_tasks,     class_name: "Task",    foreign_key: :os_id
  belongs_to :obj_type, optional: true
  has_many :vers,          as: :resource
  has_many :field_changes, as: :resource

  after_save :update_cache

  # ---------------------------------------------------------------------------
  # Cache management
  # ---------------------------------------------------------------------------

  def update_cache
    Pragmatica.update_STATUSES if defined?(Pragmatica)
  end

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  def self.cached_find(status_id)
    cached_all.find { |r| r.id == status_id }
  end

  def self.list(options = {})
    scope = where(tf: 1).order(position: :asc)
    options[:conditions] ? scope.where(options[:conditions]) : scope
  end

  def self.get(name, value)
    cached_where { |r| r.name == name && r.value == value }.first
  end

  def self.get_values(name)
    cached_where { |r| r.name == name }
  end

  def self.ids(name)
    get_values(name).map(&:id)
  end

  def self.get_hash(name)
    get_values(name).each_with_object({}) { |s, h| h[s.value] = s.id }
  end

  def self.get_hash_rev(name)
    get_values(name).each_with_object({}) { |s, h| h[s.id] = s.value }
  end

  # Override ModelLibrary#find_active for Status-specific behaviour
  def self.find_active(name, status_limit = 1, current_employee = nil)
    if name != "all" && where(name: name).exists?
      where(name: name).to_a
    else
      where("id <= ? and name = ?", status_limit, "all").to_a
    end
  end

  # -- Generic named lookups (name="all") ------------------------------------
  def self.active        = by_nv("all", "active")
  def self.inactive      = by_nv("all", "inactive")
  def self.deleted       = by_nv("all", "deleted")
  def self.archived      = by_nv("all", "archived")
  def self.master        = by_nv("all", "master")
  def self.validator_min = by_nv("all", "validator_min")
  def self.validator_max = by_nv("all", "validator_max")
  def self.template      = by_nv("all", "template")

  # -- Generic by name -------------------------------------------------------
  def self.waiting(name)  = by_nv(name, "waiting")
  def self.approved(name) = by_nv(name, "approved")
  def self.approved?(name) = by_nv(name, "approved").present?

  # -- Invites ---------------------------------------------------------------
  def self.invited  = by_nv("invites", "invited")
  def self.accepted = by_nv("invites", "accepted")
  def self.declined = by_nv("invites", "declined")
  def self.welcomed = by_nv("invites", "welcomed")

  # -- Tasks -----------------------------------------------------------------
  def self.task_completed = by_nv("tasks", "completed")

  # -- Projects --------------------------------------------------------------
  def self.project_new         = by_nv("projects", "new")
  def self.project_launched    = by_nv("projects", "launched")
  def self.project_in_progress = by_nv("projects", "in_progress")
  def self.project_completed   = by_nv("projects", "completed")
  def self.project_archived    = by_nv("projects", "archived")
  def self.project_cancelled   = by_nv("projects", "cancelled")
  def self.project_on_hold     = by_nv("projects", "on_hold")

  # -- Work Orders -----------------------------------------------------------
  def self.wo_not_started = by_nv("wos", "not_started")
  def self.wo_in_progress = by_nv("wos", "in_progress")
  def self.wo_completed   = by_nv("wos", "completed")
  def self.wo_closed      = by_nv("wos", "closed")
  def self.wo_approved    = by_nv("wos", "approved")
  def self.wo_waiting     = by_nv("wos", "waiting")
  def self.wo_cancelled   = by_nv("wos", "cancelled")
  def self.wo_deferred    = by_nv("wos", "deferred")

  # -- Loads (import/export) -------------------------------------------------
  def self.f_load = by_nv("loads", "imported")
  def self.i_load = by_nv("loads", "transformed")
  def self.t_load = by_nv("loads", "loaded")

  # -- Knowledge Base --------------------------------------------------------
  def self.draft     = by_nv("kdbs", "draft")
  def self.review    = by_nv("kdbs", "review")
  def self.published = by_nv("kdbs", "published")
  def self.retired   = by_nv("kdbs", "retired")

  def self.not_published
    cached_where { |r| r.name == "kdbs" && r.value.downcase != "published" }
  end

  def self.not_published_ids = not_published.map(&:id)

  # -- QNs -------------------------------------------------------------------
  def self.qn_new         = by_nv("qns", "new")
  def self.qn_in_progress = by_nv("qns", "in_progress")
  def self.qn_completed   = by_nv("qns", "completed")

  # -- Model Transforms ------------------------------------------------------
  def self.tr_configured = by_nv("trs", "configured")
  def self.tr_tested     = by_nv("trs", "tested")
  def self.tr_executed   = by_nv("trs", "executed")
  def self.tr_failed     = by_nv("trs", "failed")
  def self.tr_hold       = by_nv("trs", "hold")

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------

  def active?   = id == Status.active&.id
  def inactive? = id == Status.inactive&.id
  def archived? = id == Status.archived&.id

  def desc = ""

  def to_s2_fields
    %w[value description].select { |f| respond_to?(f) }
  end

  def to_s2
    value.to_s.humanize
  end

  # ---------------------------------------------------------------------------
  private
  # ---------------------------------------------------------------------------

  # Returns all statuses from Pragmatica cache if available, else DB.
  def self.cached_all
    defined?(Pragmatica) ? Pragmatica.STATUSES : all.to_a
  end

  # Filter cached_all with a block.
  def self.cached_where(&block)
    cached_all.select(&block)
  end

  # Look up a single status by name + value (case-insensitive on value).
  def self.by_nv(name, value)
    cached_where { |r| r.name == name && r.value.to_s.downcase == value.downcase }.first
  end
end
