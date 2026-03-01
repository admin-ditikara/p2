class SessionsController < ApplicationController
  def new
    redirect_to root_path if current_employee
  end

  def create
    employee = Employee.authenticate(params[:login], params[:password])
    if employee
      session[:employee_id] = employee.id
      redirect_to root_path, notice: "Welcome back, #{employee.full_name}!"
    else
      flash.now[:alert] = "Invalid username or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session[:employee_id] = nil
    redirect_to login_path, notice: "You have been signed out."
  end
end
