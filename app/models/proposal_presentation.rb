class ProposalPresentation < ActiveRecord::Base
  belongs_to :user, class_name: 'User', foreign_key: :user_id, inverse_of: :proposal_presentations
  belongs_to :acceptor, class_name: 'User', foreign_key: :acceptor_id, optional: true
  belongs_to :proposal, class_name: 'Proposal', foreign_key: :proposal_id, inverse_of: :proposal_presentations

  before_create :generate_nickname

  after_commit :send_notifications, on: :create, unless: :skip_notifications?

  protected

  def skip_notifications?
    acceptor.nil?
  end

  def generate_nickname
    ProposalNickname.generate(user, proposal)
  end

  def send_notifications
    NotificationProposalPresentationCreate.perform_async(id)
  end
end
