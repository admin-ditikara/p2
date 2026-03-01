require 'digest/sha1'

class User < ApplicationRecord
  attr_accessor :password

  def self.authenticate(email, password)
    user = find_by(email: email.to_s.downcase.strip)
    return nil unless user && user.crypted_password.present? && user.salt.present?
    user.encrypt(password) == user.crypted_password ? user : nil
  end

  def self.find_by_valid_reset_token(token)
    user = find_by(auth_token: token)
    return nil unless user && user.auth_token_expires && user.auth_token_expires > Time.now
    user
  end

  def generate_reset_token!
    self.auth_token = SecureRandom.hex(32)
    self.auth_token_expires = 1.hour.from_now
    save!(validate: false)
    auth_token
  end

  def reset_password!(new_password)
    self.salt = Digest::SHA1.hexdigest("--#{Time.now}--#{email}--")
    self.crypted_password = encrypt(new_password)
    self.auth_token = nil
    self.auth_token_expires = nil
    save!(validate: false)
  end

  def full_name
    [first_name, last_name].select(&:present?).join(' ').presence || email
  end

  protected

  def encrypt(password)
    Digest::SHA1.hexdigest("--#{salt}--#{password}--")
  end
end
