require 'digest/sha1'

class User < ApplicationRecord
  attr_accessor :password

  def self.authenticate(email, password)
    user = find_by(email: email.to_s.downcase.strip)
    return nil unless user && user.crypted_password.present? && user.salt.present?
    user.encrypt(password) == user.crypted_password ? user : nil
  end

  def full_name
    [first_name, last_name].select(&:present?).join(' ').presence || email
  end

  protected

  def encrypt(password)
    Digest::SHA1.hexdigest("--#{salt}--#{password}--")
  end
end
