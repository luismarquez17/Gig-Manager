class EnsureAllImagesPersistedInDatabase < ActiveRecord::Migration[7.1]
  def up
    # 1. Backfill PresetBudgets images to image_base64
    PresetBudget.unscoped.find_each do |preset|
      next if preset.image_base64.present?
      next unless preset.image.attached? && preset.image.blob.present?

      begin
        if preset.image.blob.service.exist?(preset.image.blob.key)
          data = preset.image.blob.download
          if data.present?
            content_type = preset.image.blob.content_type.presence || 'image/jpeg'
            encoded = Base64.strict_encode64(data)
            preset.update_column(:image_base64, "data:#{content_type};base64,#{encoded}")
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[Migration EnsureAllImagesPersistedInDatabase] PresetBudget ##{preset.id} error: #{e.message}")
      end
    end

    # 2. Backfill Users avatars to avatar_base64
    User.unscoped.find_each do |user|
      next if user.avatar_base64.present?
      next unless user.avatar.attached? && user.avatar.blob.present?

      begin
        if user.avatar.blob.service.exist?(user.avatar.blob.key)
          data = user.avatar.blob.download
          if data.present?
            content_type = user.avatar.blob.content_type.presence || 'image/jpeg'
            encoded = Base64.strict_encode64(data)
            user.update_column(:avatar_base64, "data:#{content_type};base64,#{encoded}")
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[Migration EnsureAllImagesPersistedInDatabase] User ##{user.id} error: #{e.message}")
      end
    end
  end

  def down
    # No-op: do not remove base64 data to protect persistent image storage
  end
end
