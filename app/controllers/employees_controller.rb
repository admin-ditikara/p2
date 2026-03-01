class EmployeesController < ApplicationController
  def new
    redirect_to root_path if current_employee
    @employee = Employee.new
  end

  def create
    @employee = Employee.new(employee_params)
    if @employee.save
      session[:employee_id] = @employee.id
      redirect_to root_path, notice: "Welcome, #{@employee.full_name}! Your account has been created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def employee_params
    params.require(:employee).permit(:fn, :ln, :email, :login, :password, :password_confirmation)
  end
end
