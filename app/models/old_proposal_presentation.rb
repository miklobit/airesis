class OldProposalPresentation < ActiveRecord::Base
  belongs_to :user
  belongs_to :proposal_life, inverse_of: :old_proposal_presentations
end
