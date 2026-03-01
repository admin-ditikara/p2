class UploadsController < ApplicationController
  before_action :login_required

  UPLOAD_DIR = Rails.root.join("storage", "uploads")

  def index
    @files = Dir.glob(UPLOAD_DIR.join("*"))
                .select { |f| File.file?(f) }
                .map do |path|
                  {
                    name: File.basename(path),
                    size: File.size(path),
                    modified_at: File.mtime(path)
                  }
                end
                .sort_by { |f| f[:modified_at] }
                .reverse
  end

  def create
    file = params[:file]
    unless file.present?
      redirect_to uploads_path, alert: "No file selected." and return
    end

    filename  = sanitize_filename(file.original_filename)
    dest_path = UPLOAD_DIR.join(filename)

    File.binwrite(dest_path, file.read)

    redirect_to uploads_path, notice: "\"#{filename}\" uploaded successfully."
  end

  def destroy
    filename = sanitize_filename(params[:id])
    path     = UPLOAD_DIR.join(filename)

    if File.exist?(path) && path.to_s.start_with?(UPLOAD_DIR.to_s)
      File.delete(path)
      redirect_to uploads_path, status: :see_other, notice: "\"#{filename}\" deleted."
    else
      redirect_to uploads_path, status: :see_other, alert: "File not found."
    end
  end

  def download
    filename = sanitize_filename(params[:id])
    path     = UPLOAD_DIR.join(filename)

    if File.exist?(path) && path.to_s.start_with?(UPLOAD_DIR.to_s)
      send_file path, disposition: "attachment"
    else
      redirect_to uploads_path, alert: "File not found."
    end
  end

  private

  def sanitize_filename(filename)
    File.basename(filename.to_s.gsub("\\", "/")).gsub(/[^\w.\-]/, "_")
  end
end
