class BlockedAlert < ActiveRecord::Base
  belongs_to :user, inverse_of: :blocked_alerts
  belongs_to :notification_type, inverse_of: :blocked_alerts

  validates_uniqueness_of :user, scope: :notification_type
end
