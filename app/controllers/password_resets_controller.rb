class PasswordResetsController < ApplicationController
  # Step 1: Show "enter your email" form
  def new
  end

  # Step 2: Generate token and show the reset link
  def create
    user = User.find_by(login: params[:login].to_s.strip)
    if user
      token = user.generate_reset_token!
      @reset_url = edit_password_reset_url(token)
    else
      flash.now[:alert] = "No account found with that username."
      render :new, status: :unprocessable_entity
    end
  end

  # Step 3: Show "enter new password" form
  def edit
    @user = User.find_by_valid_reset_token(params[:id])
    unless @user
      redirect_to new_password_reset_path, alert: "Reset link is invalid or has expired."
    end
  end

  # Step 4: Save new password
  def update
    @user = User.find_by_valid_reset_token(params[:id])
    unless @user
      redirect_to new_password_reset_path, alert: "Reset link is invalid or has expired."
      return
    end

    password = params[:password].to_s
    confirm  = params[:password_confirmation].to_s

    if password.length < 6
      flash.now[:alert] = "Password must be at least 6 characters."
      render :edit, status: :unprocessable_entity
    elsif password != confirm
      flash.now[:alert] = "Passwords do not match."
      render :edit, status: :unprocessable_entity
    else
      @user.reset_password!(password)
      redirect_to login_path, notice: "Password updated. Please sign in."
    end
  end
end
