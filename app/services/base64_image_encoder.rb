# frozen_string_literal: true

require "base64"
require "open3"
require "tempfile"

# Comprime y redimensiona imágenes con libvips (vipsthumbnail) antes de guardarlas en Base64.
# Reduce fotos de celular de 3-5 MB a ~30-60 KB, evitando picos de RAM en PostgreSQL y Puma.
# Si vipsthumbnail no está disponible o el archivo no es una imagen raster, usa los bytes originales sin fallar.
class Base64ImageEncoder
  COMPRESSIBLE_TYPES = %w[
    image/jpeg
    image/jpg
    image/png
    image/webp
    image/heic
    image/heif
  ].freeze

  def self.encode(data, content_type:, max_dimension: 1000, quality: 75)
    return nil if data.blank?

    normalized_type = content_type.presence || "image/jpeg"
    compressed_data, final_type = compress_if_possible(data, normalized_type, max_dimension: max_dimension, quality: quality)

    "data:#{final_type};base64,#{Base64.strict_encode64(compressed_data)}"
  end

  def self.compress_if_possible(data, content_type, max_dimension:, quality:)
    return [data, content_type] unless COMPRESSIBLE_TYPES.include?(content_type.to_s.downcase)
    # Si ya pesa menos de 60 KB, no vale la pena recomprimir
    return [data, content_type] if data.bytesize <= 60 * 1024

    input_file = Tempfile.new(["img_in", ".bin"])
    output_file = Tempfile.new(["img_out", ".jpg"])
    input_file.binmode
    input_file.write(data)
    input_file.flush
    output_path = output_file.path
    output_file.close

    # vipsthumbnail redimensiona manteniendo proporción y elimina metadatos EXIF (strip)
    _stdout, _stderr, status = Open3.capture3(
      "vipsthumbnail",
      input_file.path,
      "--size", "#{max_dimension}x#{max_dimension}",
      "-o", "#{output_path}[Q=#{quality},strip]"
    )

    if status.success? && File.exist?(output_path) && File.size(output_path) > 0 && File.size(output_path) < data.bytesize
      [File.binread(output_path), "image/jpeg"]
    else
      [data, content_type]
    end
  rescue Errno::ENOENT, StandardError => e
    Rails.logger.debug("[Base64ImageEncoder] Fallback sin compresión: #{e.message}") if defined?(Rails)
    [data, content_type]
  ensure
    input_file&.close!
    output_file&.unlink if output_file && File.exist?(output_file.path)
  end
end
