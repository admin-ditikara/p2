class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_employee, :logged_in?

  private

  def current_employee
    @current_employee ||= Employee.find_by(id: session[:employee_id]) if session[:employee_id]
  end

  def logged_in?
    current_employee.present?
  end

  def require_login
    redirect_to login_path, alert: "Please sign in to continue." unless logged_in?
  end
end
