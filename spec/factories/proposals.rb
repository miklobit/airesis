FactoryBot.define do
  factory :proposal do
    category { build(:proposal_category, :no_category) }
    proposal_type { build(:proposal_type, :standard) }
    title { Faker::Lorem.sentence }
    tags_list { %w[tag1 tag2 tag3].join(',') }
    votation { { later: 'true' } }
    quorum { BestQuorum.visible.first }
    transient do
      num_solutions { 1 }
    end
    current_user_id { create(:user).id }

    factory :public_proposal do
    end

    factory :group_proposal do
      visible_outside { true }
      transient do
        groups { [] }
      end

      after(:build) do |proposal, evaluator|
        evaluator.groups.each do |group|
          proposal.group_proposals << GroupProposal.new(group: group)
        end
      end
    end

    after(:build, &:build_sections)

    before(:build) do |proposal, evaluator|
      (evaluator.num_solutions - 1).times do |i|
        proposal.solutions.create(seq: i + 2)
      end
    end

    factory :in_debate_public_proposal do
      transient do
        debate_duration { 2 }
      end
      num_solutions { 2 }
      quorum { create(:best_quorum, percentage: 0, days_m: debate_duration) }
      current_user_id { create(:user).id }

      factory :in_vote_public_proposal do
        transient do
          vote_duration { 5 }
        end
        votation { { choise: 'new', end: vote_duration.days.from_now } }
        after(:create) do |proposal, evaluator|
          proposal.rankings.create!(user: proposal.users.first, ranking_type_id: :positive)
          Timecop.travel(evaluator.debate_duration.days.from_now) do
            proposal.check_phase(true)
            proposal.reload
            proposal.vote_period.start_votation
          end
        end
      end

      factory :abadoned_public_proposal do
        after(:create) do |proposal, evaluator|
          proposal.rankings.create(user: proposal.users.first, ranking_type_id: :negative)
          Timecop.travel(evaluator.debate_duration.days.from_now) do
            proposal.check_phase(true)
            proposal.reload
          end
        end
      end
    end
  end
end
