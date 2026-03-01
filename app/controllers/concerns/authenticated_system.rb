module AuthenticatedSystem
  extend ActiveSupport::Concern

  included do
    helper_method :current_employee, :logged_in?
  end

  def logged_in?
    current_employee.present?
  end

  def current_employee
    @current_employee ||= Employee.find_by(id: session[:employee_id]) if session[:employee_id]
  end

  # Before action to enforce login. Usage:
  #   before_action :login_required
  def login_required
    unless logged_in?
      store_location
      access_denied
    end
  end

  def access_denied
    respond_to do |format|
      format.html { redirect_to login_path, alert: "Please sign in to continue." }
      format.json { render json: { error: "Unauthorized" }, status: :unauthorized }
    end
    false
  end

  # Save the current URL so we can return after login.
  def store_location
    session[:return_to] = request.fullpath
  end

  # Redirect to the saved URL or a default.
  def redirect_back_or_default(default)
    redirect_to(session.delete(:return_to) || default)
  end
end
