require 'digest/sha1'

class Employee < ApplicationRecord
  ACTIVE_STATUS_ID = 1

  attr_accessor :password, :password_confirmation

  # Signup validations
  validates :fn,    presence: true, on: :create
  validates :ln,    presence: true, on: :create
  validates :email, presence: true, uniqueness: { case_sensitive: false }, on: :create
  validates :login, presence: true, uniqueness: { case_sensitive: false }, on: :create,
                    format: { with: /\A[a-zA-Z0-9_]+\z/, message: "only letters, numbers, and underscores" }
  validates :password, presence: true, length: { minimum: 6 }, on: :create
  validate  :password_must_match, on: :create

  before_create :set_defaults
  before_create :hash_password

  def self.authenticate(login, password)
    employee = find_by(login: login.to_s.strip, status_id: ACTIVE_STATUS_ID)
    return nil unless employee&.crypted_password.present? && employee&.salt.present?
    employee.encrypt(password) == employee.crypted_password ? employee : nil
  end

  def full_name
    [fn, ln].select(&:present?).join(' ').presence || login
  end

  def encrypt(password)
    Digest::SHA1.hexdigest("--#{salt}--#{password}--")
  end

  private

  def password_must_match
    errors.add(:password_confirmation, "doesn't match password") if password != password_confirmation
  end

  def set_defaults
    self.status_id = ACTIVE_STATUS_ID
  end

  def hash_password
    return if password.blank?
    self.salt = Digest::SHA1.hexdigest("--#{Time.now}--#{login}--")
    self.crypted_password = encrypt(password)
  end
end
