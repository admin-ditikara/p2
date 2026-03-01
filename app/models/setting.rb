class Setting < ApplicationRecord
  TITLE = "Application Setting"

  include ModelLibrary

  before_save  :validate_record
  after_create :d_after_create
  after_save   :update_cache

  belongs_to :status,   optional: true
  belongs_to :category, optional: true
  belongs_to :typ, class_name: "Lookup", foreign_key: :typ_id, optional: true
  has_many :vers,          as: :resource
  has_many :field_changes, as: :resource

  # ---------------------------------------------------------------------------
  # Cache management
  # ---------------------------------------------------------------------------

  def update_cache
    Pragmatica.update_SETTINGS if defined?(Pragmatica)
  end

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # Look up a setting by name — uses Pragmatica cache when available.
  def self.find_by_name(name)
    if defined?(Pragmatica)
      Pragmatica.SETTINGS.find { |r| r.name == name }
    else
      where(name: name).first
    end
  end

  def self.get_value(name)
    r = where(name: name, status_id: Status.active.id).first rescue where(name: name).first
    r&.value
  end

  def self.items_per_page
    where("name like ?", "items_per_page").pick(:value)&.to_i || 15
  end

  def self.database?
    val = where("name like ?", "database").pick(:value)
    val == "mysql"
  end

  def self.get_page_heading(name)
    get_setting(name, "page_headings")
  end

  def self.get_system_value(name)
    get_setting(name, "system")
  end

  def self.get_app_value(name)
    get_setting(name, "application")
  end

  def self.get_setting(name, category_name)
    c = Category.where("name like ? and value like ?", table_name, category_name).first rescue nil
    return nil unless c
    s = where("name like ? and category_id = ?", name, c.id).first
    s ? s.value : where("name like ? and category_id = ?", "default", c.id).pick(:value)
  end

  def self.product
    find_by_name("page_title_prefix") || create(name: "page_title_prefix", value: "Pragmatica")
    find_by_name("page_title_prefix").value.to_s
  end

  def self.company
    find_by_name("footer_company_name") || create(name: "footer_company_name", value: "ditikara")
    find_by_name("footer_company_name").value.to_s
  end

  def self.m_model
    rec = find_by_name("m_model_static")
    rec ? rec.desc.to_s.downcase : "yes"
  end

  def self.debug_mode
    rec = find_by_name("debug_mode") rescue nil
    rec && rec.value.to_s.downcase == "yes"
  end

  def self.sdbg(val = 1)
    rec = find_by_name("debug_mode") rescue nil
    return unless rec
    rec.value = val == 1 ? "yes" : "no"
  end

  def self.service_desk_ccno
    find_by_name("service_desk_ccno") || create(name: "service_desk_ccno", value: "6360")
    find_by_name("service_desk_ccno").value.to_s
  end

  def self.service_desk_cp
    find_by_name("service_desk_cp") || create(name: "service_desk_cp", value: (Lookup.ap7.to_s rescue ""))
    find_by_name("service_desk_cp").value.to_s
  end

  # ---------------------------------------------------------------------------
  # Seed methods
  # ---------------------------------------------------------------------------

  def self.seed_default_settings
    find_by_name("uuuuuuu") || create(name: "uuuuuuu", value: "s", status_id: 6)

    [
      [ "model_search_limit",        "100" ],
      [ "lookup_search_limit",       "100" ],
      [ "pm_look_ahead_days",        "360" ],
      [ "dependency_flag",           "0" ],
      [ "wo_latest_date_advance",    "2" ],
      [ "wo_earliest_date_advance",  "0" ],
      [ "default_labor_rate",        "60.00" ],
      [ "equipment_cost_to_location", "0" ],
      [ "tags_enabled",              "1" ],
      [ "show_task_material",        "1" ],
      [ "show_task_tool",            "1" ],
      [ "show_task_meter",           "1" ],
      [ "layout_width",              "1280" ],
      [ "default_layout",            "application" ],
      [ "page_title_prefix",         "Pragmatica" ],
      [ "wrs_title",                 "Request" ],
      [ "wos_title",                 "Service Request" ],
      [ "pms_title",                 "PM" ],
      [ "plans_title",               "Procedure" ],
      [ "facets_title",              "Equipment Attributes" ],
      [ "materials_title",           "Materials" ],
      [ "tools_title",               "Tools" ],
      [ "imacs_title",               "Transactions" ],
      [ "statuses_title",            "Statuses" ],
      [ "Wr_created",                "Work request '%s' has been created" ],
      [ "Wr_status_changed",         "Work request '%s' status has changed to '%s'" ],
      [ "Wr_assigned",               "Work request '%s' has been assigned to '%s'" ],
      [ "Task_create",               "Task '%s' has been created" ],
      [ "Task_tool_added",           "Tool has been added to task %s" ],
      [ "Task_tool_deleted",         "Tool has been deleted from task %s" ],
      [ "employees_deepcopy",        "crafts, members" ],
      [ "equipment_deepcopy",        "facets,partlists,attachables" ],
      [ "facets_deepcopy",           "facet_validation" ],
      [ "inventories_deepcopy",      "facets,attachables,vendors,manufacturers,partlists" ],
      [ "locations_deepcopy",        "attachables" ],
      [ "plans_deepcopy",            "steps" ],
      [ "steps_deepcopy",            "pmacs,reading_requests" ],
      [ "show_knowledge_bar",        "0" ],
      [ "show_left_menu",            "0" ],
      [ "m_model_static",            "yes" ]
    ].each do |name, value|
      find_by_name(name) || create(name: name, value: value)
    end

    nil
  end

  def self.seed_default_app_records
    state_abbr = {
      "AL" => "Alabama",         "AK" => "Alaska",           "AS" => "America Samoa",
      "AZ" => "Arizona",         "AR" => "Arkansas",         "CA" => "California",
      "CO" => "Colorado",        "CT" => "Connecticut",      "DE" => "Delaware",
      "DC" => "District of Columbia", "FM" => "Micronesia1", "FL" => "Florida",
      "GA" => "Georgia",         "GU" => "Guam",             "HI" => "Hawaii",
      "ID" => "Idaho",           "IL" => "Illinois",         "IN" => "Indiana",
      "IA" => "Iowa",            "KS" => "Kansas",           "KY" => "Kentucky",
      "LA" => "Louisiana",       "ME" => "Maine",            "MH" => "Islands1",
      "MD" => "Maryland",        "MA" => "Massachusetts",    "MI" => "Michigan",
      "MN" => "Minnesota",       "MS" => "Mississippi",      "MO" => "Missouri",
      "MT" => "Montana",         "NE" => "Nebraska",         "NV" => "Nevada",
      "NH" => "New Hampshire",   "NJ" => "New Jersey",       "NM" => "New Mexico",
      "NY" => "New York",        "NC" => "North Carolina",   "ND" => "North Dakota",
      "OH" => "Ohio",            "OK" => "Oklahoma",         "OR" => "Oregon",
      "PW" => "Palau",           "PA" => "Pennsylvania",     "PR" => "Puerto Rico",
      "RI" => "Rhode Island",    "SC" => "South Carolina",   "SD" => "South Dakota",
      "TN" => "Tennessee",       "TX" => "Texas",            "UT" => "Utah",
      "VT" => "Vermont",         "VI" => "Virgin Island",    "VA" => "Virginia",
      "WA" => "Washington",      "WV" => "West Virginia",    "WI" => "Wisconsin",
      "WY" => "Wyoming"
    }

    usa = Lookup.find_by(fn: "state_id", value: "USA") || Lookup.create(fn: "state_id", value: "USA")
    state_abbr.each do |abbr, state|
      Lookup.find_by(fn: "state_id", value: abbr) ||
        Lookup.create(fn: "state_id", value: abbr, description: state, parent_id: usa.id)
    end

    [
      [ "schedule_type_id", %w[Fixed Dynamic System] ],
      [ "work_type_id",     %w[PM] ],
      [ "interval_unit_id", %w[day week month year] ],
      [ "fixed_id",         %w[Yes No] ],
      [ "gender_id",        %w[M F] ],
      [ "pm_condition_id",  %w[!= < <= == > >=] ],
      [ "priority_id",      %w[0 1 2 3] ],
      [ "resource_type",    %w[Employee Equipment Location Wo Wr Task Storeroom Sequence OrgTeam
                              PrjTeam Role Pm Facet Vendor Timesheet Material Inventory Tool
                              Lookup Owner Req Project Opportunity Product Company Supplier
                              Budget Invite Mycontact Watchlist Query] ],
      [ "typ_id",           %w[integer decimal string] ]
    ].each do |fn, values|
      values.each do |v|
        Lookup.find_by(fn: fn, value: v) || Lookup.create(fn: fn, value: v)
      end
    end
  end

  def self.seed_master_records
    master_id = Status.master&.id || 5

    {
      Wr        => { sid: "REQ%y%m%d%%05d", name: "", status_id: master_id, os_id: 8,  priority_id: 29 },
      Wo        => { sid: "WOR%y%m%d%%05d", name: "", status_id: master_id, os_id: 9,  priority_id: 29 },
      Incident  => { sid: "INC%y%m%d%%05d", name: "", status_id: master_id, os_id: 9,  priority_id: 29 },
      Change    => { sid: "CHG%y%m%d%%05d", name: "", status_id: master_id, os_id: 9,  priority_id: 29 },
      Todo      => { sid: "TOD%y%m%d%%05d", name: "", status_id: master_id, os_id: 9,  priority_id: 29 },
      Vendor    => { sid: "VEN%y%m%d%%05d", name: "", status_id: master_id },
      Task      => { sid: "TSK%y%m%d%%05d", name: "", status_id: master_id, os_id: 15, priority_id: 29 },
      Req       => { sid: "RQS%y%m%d%%05d", name: "", status_id: master_id },
      Product   => { sid: "PRD%y%m%d%%05d", name: "", status_id: master_id },
      Po        => { sid: "POS%y%m%d%%05d", name: "", status_id: master_id, os_id: 53 },
      Pm        => { sid: "PPS%y%m%d%%05d", name: "", status_id: master_id },
      Plan      => { sid: "PLN%y%m%d%%05d", name: "", status_id: master_id },
      Location  => { sid: "LOC%y%m%d%%05d", name: "", status_id: master_id },
      Mycontact => { sid: "MYC%y%m%d%%05d", name: "", status_id: master_id },
      Manufacturer => { sid: "MNF%y%m%d%%05d", name: "", status_id: master_id },
      Equipment => { sid: "INF%y%m%d%%05d", name: "", status_id: master_id },
      Company   => { sid: "COM%y%m%d%%05d", name: "", status_id: master_id },
      Budget    => { sid: "BUD%y%m%d%%05d", name: "", status_id: master_id },
      Qn        => { sid: "QNS%y%m%d%%05d", name: "", status_id: master_id, os_id: Status.qn_new.to_i },
      Expense   => { sid: "EXP%y%m%d%%05d", name: "", status_id: master_id },
      Invite    => { sid: "INV%y%m%d%%05d", status_id: master_id, os_id: 65 },
      Project   => { sid: "PRJ%y%m%d%%05d", name: "", status_id: master_id, os_id: 60 },
      Event     => { sid: "PJE%y%m%d%%05d", name: "", status_id: master_id }
    }.each do |klass, attrs|
      klass.where(status_id: master_id).first_or_create(attrs) rescue nil
    end
  end

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------

  def to_s2
    name.to_s
  end

  def desc
    value.to_s
  end
end
