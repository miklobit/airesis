class BlockedAlert < ActiveRecord::Base
  belongs_to :user
  belongs_to :notification_type

  validates_uniqueness_of :user, scope: :notification_type
end
