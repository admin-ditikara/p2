module ModelLibrary
  extend ActiveSupport::Concern

  SECONDS_IN_DAY = 86_400

  class_methods do
    # Find active records (status_id <= status_limit) scoped by COSMOS options.
    def find_active(status_limit = 1, current_employee = nil)
      find_active_with_scope(
        conditions: ["#{table_name}.status_id <= ?", status_limit],
        current_employee: current_employee
      )
    end

    def count_active(status_limit = 1, current_employee = nil)
      count_with_scope(
        conditions: ["#{table_name}.status_id <= ?", status_limit],
        current_employee: current_employee
      )
    end

    # Returns a conditions hash based on the employee's COSMOS authorization rules.
    # Result: { conditions: ["cond_str", param, ...] } or nil (no restriction).
    def get_cosmos_options(current_employee, options = {})
      opt = { include_shares: true, action: "search" }.merge(options)
      cond_arr   = []
      cond_params = []

      get_rules(current_employee).each do |rule|
        rule.each_pair do |fn, val|
          if (fn =~ /_id$/ || fn =~ /_by$/) && (val.include?(0) || val.include?("0")) && val.size == 1
            cond_arr << "(#{fn} is null)"
          elsif fn == "field_id" && val.include?("notnull") && val.size == 1
            cond_arr << "(#{fn} is not null)"
          else
            cond_arr << "(#{fn} in (?))"
            cond_params << [val].flatten
          end
        end
      end

      if opt[:include_shares] && cond_arr.any?
        cond_arr    << "(id in (select resource_id from shares where resource_type=? and employee_id=?))"
        cond_params << correct_resource_type(to_s)
        cond_params << current_employee.id
      end

      cond_str = cond_arr.join(" or ")

      if cond_str.present?
        asp_mode = defined?(ASP_MODE) && ASP_MODE
        if asp_mode && current_employee && new.respond_to?("x_pragma") && current_employee.attributes["x_pragma"].present?
          cond_str = "(#{cond_str}) and (x_pragma is null or x_pragma=?)"
          return { conditions: [cond_str] + cond_params + [current_employee.attributes["x_pragma"]] }
        else
          return { conditions: ["(#{cond_str})"] + cond_params }
        end
      else
        restrictive = defined?(RESTRICTIVE_COSMOS) && RESTRICTIVE_COSMOS
        asp_mode    = defined?(ASP_MODE) && ASP_MODE
        def_ret = if restrictive
          { conditions: ["((9=9) and (created_by=?))", current_employee.id] }
        else
          { conditions: ["(9=9)"] }
        end
        if asp_mode && current_employee && new.respond_to?("x_pragma") && current_employee.attributes["x_pragma"].present?
          def_ret = if restrictive
            { conditions: ["((9=9) and (created_by=?) and (x_pragma is null or x_pragma=?))", current_employee.id, current_employee.attributes["x_pragma"]] }
          else
            { conditions: ["((9=9) and (x_pragma is null or x_pragma=?))", current_employee.attributes["x_pragma"]] }
          end
        end
        return def_ret if self <= Project rescue false
        if new.respond_to?("project_id")
          unless defined?(Pragmatica) && Pragmatica::NO_PROJECT_ID.include?(new.class.to_s)
            prj_cosmos = Project.get_cosmos_options(current_employee, include_shares: false) rescue nil
            return def_ret if prj_cosmos.nil?
            prj_ids = Project.where(prj_cosmos[:conditions]).pluck(:id) rescue []
            return { conditions: ["((project_id in (?)) or (project_id is null) or (created_by=?))", prj_ids, current_employee.to_i] }
          else
            return def_ret
          end
        else
          return def_ret
        end
      end
    end

    def count_with_scope(options = {})
      current_employee = options.delete(:current_employee)
      conditions       = options.delete(:conditions)
      cosmos           = get_cosmos_options(current_employee)
      scope = conditions ? where(conditions) : all
      scope = scope.where(cosmos[:conditions]) if cosmos
      scope.count
    end

    def find_active_with_scope(options = {})
      current_employee = options.delete(:current_employee)
      conditions       = options.delete(:conditions)
      cosmos           = get_cosmos_options(current_employee)
      scope = conditions ? where(conditions) : all
      scope = scope.where(cosmos[:conditions]) if cosmos
      scope.to_a
    end

    def get_rules(current_employee)
      return [] if current_employee.nil?
      current_employee.cosmos_cache[to_s] || []
    end

    # Walk up the STI hierarchy to find the base AR class name.
    def correct_resource_type(rt)
      return rt if rt.nil? || rt == ""
      c = rt.constantize rescue self
      c = c.superclass while c.superclass.to_s != "ActiveRecord::Base"
      c.to_s
    end

    # Update the lbl (label) field used for global search on all active records.
    def update_lbl
      return unless new.respond_to?("lbl") && new.respond_to?("update_lbl_for_search")
      cond = defined?(Pragmatica) ? Pragmatica.cond : nil
      records = cond ? find_active_with_scope(conditions: cond) : all.to_a
      records.each { |rec| rec.update_lbl_for_search; rec.save }
      records.size
    end

    # Reset sync flag before a new import.
    def reset_sync(need_ver = false)
      return 0 unless new.respond_to?("sync")
      cond = defined?(Pragmatica) ? Pragmatica.cond.dup : ["1=1"]
      cond[0] += " and sync=?"
      cond << 1
      c1 = count_with_scope(conditions: cond)
      if need_ver
        find_active_with_scope(conditions: cond).each { |rec| rec.update_column("sync", 0) }
      else
        where(cond).update_all(sync: 0)
      end
      c2 = count_with_scope(conditions: cond)
      c1.to_i - c2.to_i
    end
  end

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------

  # Instance version of correct_resource_type.
  def correct_resource_type(rt)
    return rt if rt.nil? || rt == ""
    c = rt.constantize rescue self.class
    c = c.superclass while c.superclass.to_s != "ActiveRecord::Base"
    c.to_s
  end

  # Copy x_pragma tenant tag from another object (ASP multi-tenant mode).
  def set_x_pragma(src_obj)
    return unless defined?(ASP_MODE) && ASP_MODE
    return unless src_obj.attributes["x_pragma"].present? && attributes.key?("x_pragma")
    self.x_pragma = src_obj.attributes["x_pragma"]
  end

  # Return (or build) the master template record for this model.
  def master(current_employee_id = nil)
    mr = self.class.find_by(status_id: Status.master.id) rescue nil
    if mr
      mr.status_id = Status.active.id
      if mr.respond_to?("sid")
        nextval   = Sequence.nextval(self.class.to_s.tableize) rescue 0
        mr.sid    = sprintf(Time.now.strftime(mr.sid.to_s), nextval)
      end
    else
      mr = self
    end
    if mr.respond_to?("employee_id") && current_employee_id
      mr.employee_id = current_employee_id if mr.employee_id.nil?
    end
    if current_employee_id
      current_employee = Employee.find_by(id: current_employee_id, status_id: Status.active.id) rescue nil
      mr.set_x_pragma(current_employee) if current_employee
    end
    mr.created_at = nil if mr.respond_to?("created_at")
    mr.created_by = nil if mr.respond_to?("created_by")
    mr.updated_at = nil if mr.respond_to?("updated_at")
    mr.updated_by = nil if mr.respond_to?("updated_by")
    mr
  end

  # Fetch the validator_min template record for this model.
  def validator_min
    cond = ["(status_id=?)", Status.validator_min.id]
    if self.class.superclass.to_s == "ActiveRecord::Base" && attributes.include?("type")
      cond[0] += " and (type is null)"
    end
    if respond_to?("os_id")
      default_min = self.class.where(cond + []).where("os_id is null").first rescue nil
      os_min      = self.class.where(cond).where(os_id: os_id).first rescue nil
      os_min.nil? ? default_min : os_min
    else
      self.class.where(cond).first rescue nil
    end
  end

  # Fetch the validator_max template record for this model.
  def validator_max
    cond = ["(status_id=?)", Status.validator_max.id]
    if self.class.superclass.to_s == "ActiveRecord::Base" && attributes.include?("type")
      cond[0] += " and (type is null)"
    end
    self.class.where(cond).first rescue nil
  end

  # ---------------------------------------------------------------------------
  # String representation helpers
  # ---------------------------------------------------------------------------

  def to_s2_fields
    %w[sid name value description lbl].select { |f| respond_to?(f) }
  end

  def to_s2
    if respond_to?("sid") && sid.to_s.present?
      sid.to_s
    elsif respond_to?("name") && name.to_s.present?
      name.to_s
    elsif respond_to?("value") && value.to_s.present?
      value.to_s
    elsif respond_to?("description") && description.to_s.present?
      description.to_s
    else
      id.to_s
    end
  end

  def to_s2_tree
    to_s2
  end

  def to_s
    to_s2.to_s
  end

  def to_i
    respond_to?("id") ? id : 0
  end

  def to_href(id = nil)
    _self_id = id || (new_record? ? -1 : self.id)
    "#{self.class.to_s.tableize.singularize}/#{_self_id}"
  end

  def desc
    ts  = to_s
    res = to_s2_fields.filter_map { |field| self[field] }.reject { |t| t == ts }.join(" ").strip
    res.present? ? res : ts
  end

  def desc_tree
    desc
  end

  def to_al
    0
  end

  def to_rw(_fn, _emp, _is_filter_obj = false)
    2
  end

  def to_imp
    "z"
  end

  # ---------------------------------------------------------------------------
  # Avatar / creator helpers
  # ---------------------------------------------------------------------------

  def avatar_url
    if respond_to?("created_by")
      c = Employee.find_by(id: created_by)
      if c.nil?
        "/assets/32/profile.gif"
      elsif c.user
        c.user.profile_photo_url32
      elsif c.login == "SYSTEM"
        defined?(SYSTEM_USER_IMAGE) ? SYSTEM_USER_IMAGE : "/assets/32/profile.gif"
      else
        "/assets/32/profile.gif"
      end
    else
      "/assets/32/profile.gif"
    end
  end

  def avatar_obj
    return nil unless respond_to?("created_by")
    c = Employee.find_by(id: created_by)
    return nil if c.nil? || c.login == "SYSTEM"
    c
  end

  # ---------------------------------------------------------------------------
  # Date calculation helpers
  # ---------------------------------------------------------------------------

  def task_end_date_seconds(sdate, ola)
    edate = sdate
    edate = sdate + 2 * SECONDS_IN_DAY if sdate.wday == 6
    edate = sdate + SECONDS_IN_DAY     if sdate.wday == 0
    ola.times do
      edate += SECONDS_IN_DAY
      edate += SECONDS_IN_DAY if edate.wday == 6
      edate += SECONDS_IN_DAY if edate.wday == 0
    end
    edate
  end

  def task_end_date(sdate, ola, wd = 1..5)
    work_days = wd.to_a
    edate = sdate
    ola.times do
      edate += 1
      edate += 1 if edate.wday == 6 && !work_days.include?(edate.wday)
      edate += 1 if edate.wday == 0 && !work_days.include?(edate.wday)
    end
    edate
  end

  # ---------------------------------------------------------------------------
  # Versioning
  # ---------------------------------------------------------------------------

  def create_version(old_self)
    return nil if old_self.nil?
    changed_attributes = {}
    old_self.attributes.each_pair do |k, v|
      next if %w[updated_by updated_at].include?(k)
      changed_attributes[k] = v if attributes[k] != v
    end
    return nil if changed_attributes.empty?

    begin
      version_class = "#{old_self.class}Version".constantize
      h = old_self.attributes.except("id")
      v = version_class.new(h) rescue nil
      self.versions << v if v
    rescue NameError
      # No version class defined for this model
    end

    if respond_to?("vers")
      h1 = { "resource" => self }
      if respond_to?("updated_by")
        h1["created_by"] = updated_by
        h1["updated_by"] = updated_by
      end
      ver = Ver.create(h1)
      changed_attributes.each_pair do |k1, v1|
        next if k1 == "lbl"
        h    = h1.clone
        f    = Field.find_by(tn: self.class.to_s.tableize, fn: k1.to_s) rescue nil
        @ov  = v1
        @nv  = attributes[k1]
        if f && f.fn =~ /_id$/
          if f.lookup == 1
            h["ov_id"] = @ov
            h["nv_id"] = @nv
            @ovl = Lookup.find_by(id: @ov)
            @nvl = Lookup.find_by(id: @nv)
          elsif f.fn == "os_id"
            h["ov_id"] = @ov
            h["nv_id"] = @nv
            @ovl = Status.find_by(id: @ov) || "nil old"
            @nvl = Status.find_by(id: @nv) || "nil new"
          else
            h["ov_id"] = @ov
            h["nv_id"] = @nv
            base_class = f.fn.gsub(/_id$/, "").classify
            @ovl = base_class.constantize.find_by(id: @ov) rescue nil
            @nvl = base_class.constantize.find_by(id: @nv) rescue nil
          end
        else
          @ovl = @ov
          @nvl = @nv
        end
        h["field"] = f
        h["fn"]    = k1.to_s
        h["ov"]    = @ovl.to_s
        h["nv"]    = @nvl.to_s
        h["employee_id"] = updated_by
        ver.field_changes << FieldChange.new(h)
      end
      self.vers << ver
      return ver
    end
    nil
  end

  # ---------------------------------------------------------------------------
  # Record validation (validator_min / validator_max records)
  # ---------------------------------------------------------------------------

  def validate_record
    old_self = new_record? ? nil : self.class.find_by(id: self.id)
    ret      = true

    if respond_to?("parent_id") && respond_to?("ancestors")
      if ancestors.include?(self)
        errors.add("parent_id", "Invalid parent record. Choose another parent record")
        ret = false
      end
    end

    if respond_to?("resource_type")
      if resource_type == ""
        self.resource_type = nil
        self.resource_id   = nil
      end
      self.resource_type = correct_resource_type(resource_type) if resource_type
    end

    if respond_to?("object_type")
      if object_type == ""
        self.object_type = nil
        self.object_id   = nil
      end
      self.object_type = correct_resource_type(object_type) if object_type
    end

    creator = nil
    updater = nil
    if respond_to?("created_by")
      creator = Employee.find_by(id: created_by)
      self.creator_id = created_by if respond_to?("creator_id")
    end
    if respond_to?("updated_by")
      updater = Employee.find_by(id: updated_by)
      self.updater_id = updated_by if respond_to?("updater_id")
    end

    asp_mode = defined?(ASP_MODE) && ASP_MODE
    if asp_mode && attributes.key?("x_pragma")
      if new_record?
        if creator
          set_x_pragma(creator)
        elsif updater
          set_x_pragma(updater)
        elsif attributes["x_pragma"].blank?
          errors.add("x_pragma", "Unable to create record due to x_pragma empty")
          ret = false
        end
      else
        unless attributes["x_pragma"].blank?
          checker = updater || creator
          if checker
            if checker.attributes["x_pragma"].present? && attributes["x_pragma"] != checker.attributes["x_pragma"]
              errors.add("x_pragma", "You cannot update this record")
              ret = false
            end
          else
            errors.add("x_pragma", "You cannot update this record")
          end
        else
          checker = updater || creator
          if checker
            if checker.attributes["x_pragma"].present?
              errors.add("x_pragma", "You cannot update this record")
              ret = false
            end
          else
            errors.add("x_pragma", "You cannot update this record")
            ret = false
          end
        end
      end
    end

    # Validate type-cast integrity for each attribute
    attributes.each_pair do |k, _v|
      next if %w[id status_id updated_at updated_on updated_by created_on created_at created_by].include?(k)
      col  = self.class.columns_hash[k.to_s]
      next unless col
      typ  = col.type.to_s
      case typ
      when "decimal"
        before_val = attribute_before_type_cast(k).to_s
        after_val  = if attribute_before_type_cast(k).to_s.index(".").nil?
          attributes[k].to_s.split(".").first.to_s
        else
          if attribute_before_type_cast(k).to_s.count(".") > 1
            errors.add(k, "Value '#{before_val}' has multiple decimal points")
            ret = false
            next
          else
            before_split = attribute_before_type_cast(k).to_s.split(".")
            after_split  = attributes[k].to_s.split(".")
            before_val   = "#{before_split[0].to_s.strip.gsub(/^0*/, '')}.#{before_split[1].to_s.strip.gsub(/0*$/, '')}"
            "#{after_split[0].to_s.strip.gsub(/^0*/, '')}.#{after_split[1].to_s.strip.gsub(/0*$/, '')}"
          end
        end
      when "date", "datetime"
        if typ == "datetime" && !self[k].nil?
          begin
            self_k = self[k].is_a?(Date) ? self[k].to_time : self[k]
            tmp_t  = Time.local(self_k.year, self_k.month, self_k.day, self_k.hour, self_k.min, self_k.sec, 0)
            self[k] = DateTime.civil(tmp_t.year, tmp_t.month, tmp_t.day, tmp_t.hour, tmp_t.min, tmp_t.sec)
          rescue => e
            errors.add(k, "Invalid value '#{self[k]}'")
          end
        end
        next
      else
        before_val = attribute_before_type_cast(k).to_s
        after_val  = attributes[k].to_s
      end
      if before_val != after_val && ret
        errors.add(k, "Invalid value '#{before_val}'")
        ret = false
      end
    end

    status_master    = Status.master.id    rescue nil
    status_val_min   = Status.validator_min.id rescue nil
    status_val_max   = Status.validator_max.id rescue nil

    if [status_master, status_val_min, status_val_max].include?(status_id)
      create_version(old_self) if ret
      return ret
    end

    v_min = validator_min
    v_max = validator_max
    cua   = []

    table_nm = self.class.to_s.tableize

    if v_min
      v_min.attributes.each_pair do |k, v|
        next if v.nil? || v.to_s.empty? || %w[id status_id updated_at updated_on updated_by created_on created_at created_by].include?(k)
        col  = v_min.class.columns_hash[k.to_s]
        next unless col
        case col.type.to_s
        when "date", "datetime"
          if attributes[k].nil?
            em = (Em.error_for_field(table_nm, k, "empty") rescue nil)
            errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> is empty")
            ret = false
          elsif attributes[k] < v
            em = (Em.error_for_field(table_nm, k, "less") rescue nil)
            errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> cannot be before #{v}")
            ret = false
          end
        when "integer", "decimal"
          if attributes[k].nil?
            em = (Em.error_for_field(table_nm, k, "empty") rescue nil)
            errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> is empty")
            ret = false
          elsif attributes[k] < v
            em = (Em.error_for_field(table_nm, k, "less") rescue nil)
            errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> cannot be less than #{v}")
            ret = false
          end
        when "string", "text"
          if attributes[k].nil?
            em = (Em.error_for_field(table_nm, k, "empty") rescue nil)
            errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> is empty")
            ret = false
          elsif attributes[k].to_s.size < v.to_s.size
            em = (Em.error_for_field(table_nm, k, "short") rescue nil)
            errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> should be at least #{v.to_s.size} characters long")
            ret = false
          else
            cua << k if v.to_s.upcase[0, 1] == "U"
          end
        end
      end
    end

    if v_max
      v_max.attributes.each_pair do |k, v|
        next if v.nil? || v.to_s.empty? || %w[id status_id updated_at updated_on updated_by created_on created_at created_by].include?(k)
        col  = v_max.class.columns_hash[k.to_s]
        next unless col
        case col.type.to_s
        when "date", "datetime"
          if attributes[k].nil?
            em = (Em.error_for_field(table_nm, k, "empty") rescue nil)
            errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> is empty")
            ret = false
          elsif attributes[k] > v
            em = (Em.error_for_field(table_nm, k, "more") rescue nil)
            errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> should be after #{v}")
            ret = false
          end
        when "integer", "decimal"
          if attributes[k].nil?
            em = (Em.error_for_field(table_nm, k, "empty") rescue nil)
            errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> is empty")
            ret = false
          elsif attributes[k] > v
            em = (Em.error_for_field(table_nm, k, "more") rescue nil)
            errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> cannot be more than #{v}")
            ret = false
          end
        when "string", "text"
          if attributes[k].nil?
            em = (Em.error_for_field(table_nm, k, "empty") rescue nil)
            errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> is empty")
            ret = false
          elsif attributes[k].to_s.size > v.to_s.size
            em = (Em.error_for_field(table_nm, k, "long") rescue nil)
            errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> cannot be longer than #{v.to_s.size} characters")
            ret = false
          else
            cua << k if v.to_s.upcase[0, 1] == "U"
          end
        end
      end
    end

    cua.flatten.sort.uniq.each do |k|
      asp_mode = defined?(ASP_MODE) && ASP_MODE
      u_size = if asp_mode && attributes["x_pragma"].present? && respond_to?("x_pragma")
        self.class.where(["id<>? and #{k}=? and status_id<? and x_pragma=?", id.to_i, attributes[k], Status.deleted.id, attributes["x_pragma"]]).count
      else
        self.class.where(["id<>? and #{k}=? and status_id<?", id.to_i, attributes[k], Status.deleted.id]).count
      end
      if u_size > 0
        em = (Em.error_for_field(table_nm, k, "unique") rescue nil)
        errors.add(k, em ? em.value : "<b>#{self.class.human_attribute_name(k)}</b> is not unique")
        ret = false
      end
    end

    if ret
      unless old_self.nil?
        ver = create_version(old_self)
        if ver
          watch = defined?(WATCH_AND_NOTIFY) && WATCH_AND_NOTIFY
          if watch
            osid   = respond_to?("os_id") ? os_id : nil
            prid   = respond_to?("priority_id") ? priority_id : nil
            restyp = correct_resource_type(self.class.to_s)
            D.create(resource_type: restyp, resource_id: id, ver: ver, os_id: osid, priority_id: prid)
          end
        end
      end
      alarm_plan(old_self)
    end

    ret
  end

  # Create a notification record after a new record is created.
  def d_after_create
    watch  = defined?(WATCH_AND_NOTIFY) && WATCH_AND_NOTIFY
    return unless watch
    osid   = respond_to?("os_id") ? os_id : nil
    prid   = respond_to?("priority_id") ? priority_id : nil
    restyp = correct_resource_type(self.class.to_s)
    D.create(resource_type: restyp, resource_id: id, ver: nil, os_id: osid, priority_id: prid)
  end

  # ---------------------------------------------------------------------------
  # Posting / activity feed
  # ---------------------------------------------------------------------------

  def do_post(action, employee, text, project_id = nil)
    system_emp = defined?(Employee::_SYSTEM) ? Employee::_SYSTEM : nil
    system_generated = %w[internal_post customer_post new].include?(action) ? 0 : 1
    posts << Post.new(
      action:           action,
      created_by:       employee ? employee.id : system_emp,
      post_text:        text,
      project_id:       project_id,
      system_generated: system_generated
    )
  end

  def all_posts
    respond_to?("posts") ? posts.where("system_generated != 1 or system_generated is null") : []
  end

  def all_posts_text(status_limit = 1)
    all_posts.each_with_object("") do |p, str|
      next if p.status_id > status_limit
      str << "[#{p.post_time}#{p.creator ? ' - ' + p.creator.login : ''}] #{p.resource_type.to_s.upcase}\n#{p.post_text}\n"
    end
  end

  # ---------------------------------------------------------------------------
  # Voting / rating
  # ---------------------------------------------------------------------------

  def up_votes
    respond_to?("hits") ? hits.where("val > 0").count : 0
  end

  def down_votes
    respond_to?("hits") ? hits.where("val < 0").count : 0
  end

  def get_hits
    respond_to?("hits") ? hits.where(val: 0).count : 0
  end

  def rating
    return 0.0 unless respond_to?("pegs")
    r = pegs.sum(:val).to_i * 10
    c = pegs.count.to_i
    c.zero? ? 0.0 : (r / c) / 10.0
  end

  # ---------------------------------------------------------------------------
  # Resource sharing
  # ---------------------------------------------------------------------------

  def get_shared_with
    return [] if new_record?
    restyp = correct_resource_type(self.class.to_s)
    Share.where(resource_type: restyp, resource_id: id).filter_map { |s| s.employee&.id }
  end

  def get_shared_with_ro
    return [] if new_record?
    restyp = correct_resource_type(self.class.to_s)
    ids    = []
    prj    = if is_a?(Project)
      self
    elsif respond_to?("project_id") && !(defined?(Pragmatica) && Pragmatica::NO_PROJECT_ID.include?(self.class.to_s))
      project rescue nil
    end
    return ids unless prj
    prj.team_mems.each do |mem|
      e = Employee.find_by(id: mem.employee_id)
      next if e.nil?
      e.cosmos_cache = {}
      e.belongs_to_cosmos.each do |cosmo|
        cosmo.rules.each do |rule|
          next if rule.resource_type != restyp
          e.cosmos_cache[rule.resource_type] ||= []
          employee_id = e.id
          @rule_val = eval(rule.value) rescue nil
          e.cosmos_cache[rule.resource_type] << { rule.fn => [@rule_val].flatten }
        end
      end
      e_cosmos = self.class.get_cosmos_options(e) rescue nil
      e_cond   = e_cosmos ? e_cosmos[:conditions] : ["(status_id<=?)", Status.active.id]
      o2 = self.class.where(e_cond).find_by(id: id) rescue nil
      ids << e.id if o2
    end
    ids
  end

  def set_shared_with(ids, created_by = nil)
    return [] if new_record?
    restyp          = correct_resource_type(self.class.to_s)
    old_employee_ids = Share.where(resource_type: restyp, resource_id: id).pluck(:employee_id)
    new_employee_ids = ids
    to_destroy = old_employee_ids - new_employee_ids
    to_create  = new_employee_ids - old_employee_ids
    Share.where(resource_type: restyp, resource_id: id, employee_id: to_destroy).destroy_all
    to_create.each { |e_id| Share.create(employee_id: e_id, resource: self, typ: self.class.to_s, created_by: created_by) }
    get_shared_with
  end

  # ---------------------------------------------------------------------------
  # SLA / alarm planning
  # ---------------------------------------------------------------------------

  def alarm_plan(old_self)
    self_class = self.class.to_s
    return if self_class == "Slo"
    return unless %w[Incident Task Change].include?(self_class)
    ot = ObjType.by_name(self_class) rescue nil
    return if ot.nil?
    slos = Slo.where(obj_type_id: ot.to_i, status_id: Status.active.id)
    return if slos.empty?
    pri_id = if respond_to?("priority")
      priority.to_i
    elsif respond_to?("priority_id")
      priority_id
    end
    active_slos = slos.select { |r| r.priority_id == pri_id }
    alarm_gen_plan(old_self, active_slos) if respond_to?("alarm_gen_plan")
  end

  def alarm_delete_current_plan
    restyp = correct_resource_type(self.class.to_s)
    Alarm.where(resource_type: restyp, resource_id: to_i).delete_all
  end
end
