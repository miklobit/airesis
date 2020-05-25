class ParticipationRole < ActiveRecord::Base
  ADMINISTRATOR = 'amministratore'

  has_many :group_participations
  has_many :users, through: :group_participations, class_name: 'User'
  belongs_to :group, optional: true

  scope :common, -> { where(id: ParticipationRole.admin.id) }

  validates_uniqueness_of :name, scope: :group_id
  validates_presence_of :name, :description

  # before removing the role we need to assign the default role to all users associated with this role
  before_destroy :change_participation_roles

  def change_participation_roles
    group_participations.update_all(participation_role_id: group.participation_role_id) if group.present?
  end

  def self.admin
    ParticipationRole.find_by(name: ADMINISTRATOR, group_id: nil)
  end
end
