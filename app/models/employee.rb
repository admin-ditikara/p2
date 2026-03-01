require 'digest/sha1'

class Employee < ApplicationRecord
  ACTIVE_STATUS_ID = 1

  attr_accessor :password

  def self.authenticate(login, password)
    employee = find_by(login: login.to_s.strip, status_id: ACTIVE_STATUS_ID)
    return nil unless employee&.crypted_password.present? && employee&.salt.present?
    employee.encrypt(password) == employee.crypted_password ? employee : nil
  end

  def full_name
    [fn, ln].select(&:present?).join(' ').presence || login
  end

  protected

  def encrypt(password)
    Digest::SHA1.hexdigest("--#{salt}--#{password}--")
  end
end
