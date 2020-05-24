require 'rails_helper'
require 'requests_helper'
require 'cancan/matchers'

RSpec.describe 'check if quorums are working correctly', :js do
  let(:user) { create(:user) }
  let(:group) { create(:group, current_user_id: user.id) }
  let(:quorum) { create(:best_quorum, group_quorum: GroupQuorum.new(group: group)) } # min participants is 10% and good score is 50%. vote quorum 0, 50%+1
  let(:proposal) do
    create(:group_proposal, quorum: quorum, current_user_id: user.id,
                            group_proposals: [GroupProposal.new(group: group)],
                            votation: { choise: 'new', start: 10.days.from_now, end: 14.days.from_now })
  end

  before do
    load_database
  end

  def vote(klass = 'votegreen')
    visit group_proposal_path(group, proposal)
    expect(page).to have_content(I18n.t('pages.proposals.vote_panel.single_title'))
    expect(page).to have_content(proposal.secret_vote ? I18n.t('pages.proposals.vote_panel.secret_vote') : I18n.t('pages.proposals.vote_panel.clear_vote'))
    page.execute_script 'window.confirm = function () { return true }'
    find(".#{klass}").click
    expect(page).to have_content(I18n.t('votations.create.confirm'))
    proposal.reload
  end

  def vote_schulze(id)
    visit group_proposal_path(group, proposal)
    expect(page.html).to include(I18n.t('pages.proposals.vote_panel.schulze_title'))
    expect(page).to have_content(proposal.secret_vote ? I18n.t('pages.proposals.vote_panel.secret_vote') : I18n.t('pages.proposals.vote_panel.clear_vote'))

    page.execute_script "el = $('.list-group-item[data-id=#{id}]');
el.parents('.vote-items-external').prev('.vote-items-external').find('.vote-items').append(el);"

    page.execute_script 'window.confirm = function () { return true }'
    click_button I18n.t('pages.proposals.show.vote_button')
    expect(page).to have_content(I18n.t('votations.create.confirm'))
    expect(page.html).not_to include(I18n.t('pages.proposals.vote_panel.schulze_title'))
    expect(page).to have_content(I18n.t('pages.proposals.vote_panel.results_time', when: (I18n.l UserVote.last.created_at)))
    proposal.reload
  end

  it 'they can vote in a simple way and the proposal get accepted' do
    # populate the group
    19.times do
      user2 = create(:user)
      create_participation(user2, group)
    end
    # we now have 50 users in the group which can participate into a proposal

    expect(group.scoped_participants(:participate_proposals).count).to be(20)
    proposal # we create the proposal with the assigned quorum
    expect(proposal.quorum.valutations).to be(2 + 1) # calculated is ()0.1*20) + 1
    expect(proposal.quorum.good_score).to be 50 # copied
    expect(proposal.quorum.assigned).to be_truthy # copied

    group.participants.sample(10).each do |user|
      proposal.rankings.find_or_create_by(user_id: user.id) do |ranking|
        ranking.ranking_type_id = RankingType::POSITIVE
      end
    end

    proposal.reload

    expect(proposal.valutations).to be 10
    expect(proposal.rank).to be 100
    expect(proposal).to be_in_valutation

    proposal.check_phase(true)
    proposal.reload

    expect(proposal).to be_waiting

    proposal.vote_period.start_votation
    proposal.reload
    expect(proposal).to be_voting

    expect(group.scoped_participants(:vote_proposals).count).to be(20)

    expect(Ability.new(user)).to be_able_to(:vote, proposal)
    login_as user, scope: :user
    vote
    expect(proposal.vote.positive).to eq(1)

    logout :user

    users = group.participants.where.not(users: { id: user.id }).sample(4)
    expect(Ability.new(users[0])).to be_able_to(:vote, proposal)
    login_as users[0], scope: :user
    vote
    expect(proposal.vote.positive).to eq(2)

    logout :user

    login_as users[1], scope: :user
    vote('votered')
    expect(proposal.vote.positive).to eq(2)
    expect(proposal.vote.negative).to eq(1)

    logout :user

    login_as users[2], scope: :user
    expect(UserVote.find_by(user_id: users[2].id, proposal_id: proposal.id)).to be_nil
    vote('voteyellow')
    expect(proposal.vote.positive).to eq(2)
    expect(proposal.vote.negative).to eq(1)
    expect(proposal.vote.neutral).to eq(1)

    logout :user

    login_as users[3], scope: :user
    vote
    expect(proposal.vote.positive).to eq(3)
    expect(proposal.vote.negative).to eq(1)
    expect(proposal.vote.neutral).to eq(1)

    logout :user

    proposal.close_vote_phase
    proposal.reload
    expect(proposal.quorum.vote_valutations).to be(1)
    expect(proposal).to be_accepted
  end

  it 'they can vote in a simple way and the proposal get rejected' do
    # populate the group
    29.times do
      user2 = create(:user)
      create_participation(user2, group)
    end
    # we now have 50 users in the group which can participate into a proposal

    proposal # we create the proposal with the assigned quorum

    group.participants.sample(10).each do |user|
      proposal.rankings.find_or_create_by(user_id: user.id) do |ranking|
        ranking.ranking_type_id = RankingType::POSITIVE
      end
    end

    proposal.reload

    expect(proposal.valutations).to be 10
    expect(proposal.rank).to be 100
    expect(proposal).to be_in_valutation

    proposal.check_phase(true)
    proposal.reload

    expect(proposal).to be_waiting

    proposal.vote_period.start_votation
    proposal.reload
    expect(proposal).to be_voting

    expect(group.scoped_participants(:vote_proposals).count).to be(30)

    users = group.participants.sample(4)
    expect(Ability.new(users[0])).to be_able_to(:vote, proposal)
    login_as users[0], scope: :user
    vote('votered')
    expect(proposal.vote.positive).to eq(0)
    expect(proposal.vote.negative).to eq(1)

    logout :user

    login_as users[1], scope: :user
    vote('votered')
    expect(proposal.vote.positive).to eq(0)
    expect(proposal.vote.negative).to eq(2)

    logout :user

    login_as users[2], scope: :user
    vote('voteyellow')
    expect(proposal.vote.positive).to eq(0)
    expect(proposal.vote.negative).to eq(2)
    expect(proposal.vote.neutral).to eq(1)

    logout :user

    login_as users[3], scope: :user
    vote('votered')
    expect(proposal.vote.positive).to eq(0)
    expect(proposal.vote.negative).to eq(3)
    expect(proposal.vote.neutral).to eq(1)

    logout :user

    proposal.close_vote_phase
    proposal.reload
    expect(proposal).to be_rejected
  end

  it 'they can vote in a schulze way and the proposal get accepted' do
    # populate the group
    9.times do
      user2 = create(:user)
      create_participation(user2, group)
    end
    # we now have 10 users in the group which can participate into a proposal

    expect(group.scoped_participants(:participate_proposals).count).to be(10)
    proposal # we create the proposal with the assigned quorum
    expect(proposal.quorum.valutations).to be(1 + 1) # calculated is (0.1*10) + 1
    expect(proposal.quorum.good_score).to be 50 # copied
    expect(proposal.quorum.assigned).to be_truthy # copied

    group.participants.sample(3).each do |user|
      proposal.rankings.find_or_create_by(user_id: user.id) do |ranking|
        ranking.ranking_type_id = RankingType::POSITIVE
      end
    end

    proposal.reload
    add_solution(proposal)
    expect(proposal.solutions.count).to be 2
    expect(proposal.valutations).to be 3
    expect(proposal.rank).to be 100
    expect(proposal).to be_in_valutation

    proposal.check_phase(true)
    proposal.reload

    expect(proposal).to be_waiting

    proposal.vote_period.start_votation
    proposal.reload
    expect(proposal).to be_voting

    expect(group.scoped_participants(:vote_proposals).count).to be(10)

    group.participants.sample(4).each do |user1|
      expect(Ability.new(user1)).to be_able_to(:vote, proposal)
      login_as user1, scope: :user
      vote_schulze(proposal.solutions[1].id)
      logout :user
    end

    proposal.close_vote_phase
    proposal.reload
    expect(proposal).to be_accepted
    expect(proposal.schulze_votes.sum(:count)).to be 4

    expect(proposal.solutions[0].schulze_score).to be 0
    expect(proposal.solutions[1].schulze_score).to be 1
  end

  it 'they can vote in a schulze way and the proposal get rejected (no votes)' do
    # populate the group
    9.times do
      user2 = create(:user)
      create_participation(user2, group)
    end
    # we now have 10 users in the group which can participate into a proposal

    proposal # we create the proposal with the assigned quorum

    group.participants.sample(3).each do |user|
      proposal.rankings.find_or_create_by(user_id: user.id) do |ranking|
        ranking.ranking_type_id = RankingType::POSITIVE
      end
    end

    proposal.reload
    add_solution(proposal)

    proposal.check_phase(true)
    proposal.reload

    proposal.vote_period.start_votation
    proposal.reload

    proposal.close_vote_phase
    proposal.reload
    expect(proposal).to be_rejected
    expect(proposal.schulze_votes.sum(:count)).to be 0

    expect(proposal.solutions[0].schulze_score).to be 0
    expect(proposal.solutions[1].schulze_score).to be 0
  end

  it 'they can see vote results' do
    # populate the group
    9.times do
      user2 = create(:user)
      create_participation(user2, group)
    end
    # we now have 10 users in the group which can participate into a proposal

    proposal # we create the proposal with the assigned quorum

    group.participants.each do |user|
      proposal.rankings.find_or_create_by(user_id: user.id) do |ranking|
        ranking.ranking_type_id = RankingType::POSITIVE
      end
    end

    proposal.reload

    proposal.check_phase(true)
    proposal.reload

    proposal.vote_period.start_votation
    proposal.reload
    expect(proposal).to be_voting

    group.participants.each do |user|
      vote = UserVote.new(user_id: user.id, proposal_id: proposal.id)
      vote.vote_type_id = VoteType::POSITIVE
      vote.save
      proposal.vote.positive += 1
      proposal.vote.save
    end

    proposal.vote_period.end_votation
    proposal.reload
    expect(proposal).to be_voted
    expect(proposal).to be_accepted

    user = group.participants.sample

    login_as user, scope: :user
    visit group_proposal_path(group, proposal)

    expect(page).to have_content I18n.t('pages.proposals.results.total', count: 10)
    expect(proposal.vote.number).to eq(10)
    logout :user
  end
end
