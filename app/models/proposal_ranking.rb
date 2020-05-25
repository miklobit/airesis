class ProposalRanking < ActiveRecord::Base
  belongs_to :user
  belongs_to :proposal

  POSITIVE = 1
  NEGATIVE = 3

  scope :positives, -> { where(ranking_type_id: POSITIVE) }
  scope :negatives, -> { where(ranking_type_id: NEGATIVE) }

  enum ranking_type_id: { positive: 1, neutral: 2, negative: 3 }

  after_save :update_counter_cache
  after_save :check_proposal_state
  after_destroy :update_counter_cache

  after_commit :send_notifications, on: :create

  protected

  def update_counter_cache
    rankings = proposal.rankings
    nvalutations = rankings.count
    num_pos = rankings.where(ranking_type_id: POSITIVE).count
    res = num_pos.to_f / nvalutations
    ranking = nvalutations > 0 ? res * 100 : 0
    proposal.update_columns(valutations: nvalutations, rank: ranking.round)
  end

  # invia le notifiche quando un utente valuta la proposta
  # le notifiche vengono inviate ai creatori e ai partecipanti alla proposta
  def send_notifications
    NotificationProposalRankingCreate.perform_async(id)
  end

  def check_proposal_state
    proposal.check_phase
  end
end
