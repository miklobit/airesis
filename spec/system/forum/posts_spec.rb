require 'rails_helper'
require 'requests_helper'
require 'cancan/matchers'

RSpec.describe 'posts', :js do
  let(:user) { create(:user) }
  let(:group) { create(:group, current_user_id: user.id) }
  let(:free_category) { create(:frm_category, group: group, visible_outside: true) }
  let(:forum) { create(:frm_forum, group: group, category: free_category) }
  let(:topic) { create(:approved_topic, forum: forum, user: user) }

  before do
    load_database
    topic
  end

  context 'not signed in users' do
    it 'cannot begin to post a reply' do
      visit new_group_forum_topic_post_path(group, topic.forum, topic)
      expect(page).to have_current_path new_user_session_path
    end
  end

  context 'posts with deleted users' do
    it 'can be viewed' do
      first_post = topic.posts.first
      first_post.update_column(:user_id, nil)
      visit group_forum_topic_path(group, forum, topic)
      expect(page).to have_content(topic.subject)
    end
  end

  context 'signed in users' do
    before do
      login_as user, scope: :user
      visit group_forum_topic_path(group, forum, topic)
    end

    context 'replying' do
      before do
        within_first_post do
          click_link('Reply')
        end
      end

      context 'to a topic with multiple pages' do
        it 'redirects to the last page' do
          create_list(:post, 20, topic: topic)
          text = Faker::Lorem.paragraph
          fill_in_ckeditor 'frm_post_text', with: text
          click_button 'Post Reply'

          expect(page).to have_content(text)
          expect(page).not_to have_content(topic.posts.first.text)
        end
      end

      context 'to an unlocked topic' do
        it 'shows the topic we are replying to' do
          expect(page).to have_content(topic.posts.first.text)
        end

        it 'can post a reply' do
          text = Faker::Lorem.paragraph
          fill_in_ckeditor 'frm_post_text', with: text
          click_button 'Post Reply'
          expect(page).to have_content('Your reply has been posted')
          expect(page).to have_content("in reply to #{topic.posts.first.user.name}")
        end
      end

      context 'to a locked topic' do
        it 'cannot post a reply' do
          topic.lock_topic!

          text = Faker::Lorem.paragraph
          fill_in_ckeditor 'frm_post_text', with: text
          click_button 'Post Reply'
          expect(page).to have_content('You cannot reply to a locked topic')
        end
      end

      it 'cannot post a reply to a topic with blank text' do
        click_button 'Post Reply'
        expect(page).to have_content('can not be blank')
      end
    end

    context 'quoting' do
      it 'cannot quote deleted post' do
        other_user = create(:user)
        topic.posts << build(:post, topic: topic, user: other_user)
        @second_post = topic.posts[1]

        visit group_forum_topic_path(group, forum, topic)
        @second_post.delete

        within_second_post do
          click_link('Quote')
        end

        expect(page).to have_content(I18n.t('frm.post.cannot_quote_deleted_post'))
      end
    end

    context 'editing posts in topics' do
      before do
        other_user = create(:user)
        topic.posts << build(:post, topic: topic, user: other_user)
        @second_post = topic.posts[1]
      end

      it 'can edit their own post' do
        visit group_forum_topic_path(group, forum, topic)
        within_first_post do
          click_link('Edit')
        end
        sleep 5
        text = Faker::Lorem.paragraph
        fill_in_ckeditor 'frm_post_text', with: text

        click_button 'Edit'
        expect(page).to have_content('Your post has been edited')
        expect(page).to have_content(text)
      end

      # TODO: do not test in system test but request
      it "if you are group admin you should be allowed to edit a post you don't own", :ignore_javascript_errors do
        visit edit_group_forum_topic_post_path(group, forum, topic, @second_post)
        expect(page).not_to have_content(I18n.t('error.error_302.title'))
      end

      it 'displays edit link on posts you own' do
        visit group_forum_topic_path(group, forum, topic)
        within_first_post do
          expect(page).to have_content('Edit')
        end
      end
    end

    context 'deleting posts in topics' do
      context 'topic contains two posts' do
        before do
          @user = create(:user)
          topic.posts << build(:post, topic: topic, created_at: 1.day.from_now, user: @user)
        end

        it "shows correct 'started by' and 'last post' information" do
          visit group_forum_path(group, forum)
          within('.topic .started-by') do
            expect(page).to have_content(user.name)
          end

          within('.topic .latest-post') do
            expect(page).to have_content(@user.name)
          end
        end

        it 'can delete their own post' do
          visit group_forum_topic_path(group, forum, topic)
          within_first_post do
            click_link('Delete')
            page.driver.browser.switch_to.alert.accept
          end
          expect(page).to have_content('Your post has been deleted')
        end

        it 'can delete posts by others' do
          visit group_forum_topic_path(group, forum, topic)
          other_post = topic.posts.last
          expect(Ability.new(user)).to be_able_to(:destroy, other_post)
        end
      end

      context 'topic contains one post' do
        before do
          visit group_forum_topic_path(group, forum, topic)
        end

        it 'topic is deleted if only post' do
          expect(Frm::Topic.count).to eq 1
          within_first_post do
            click_link('Delete')
            page.driver.browser.switch_to.alert.accept
          end
          expect(page).to have_content(I18n.t('frm.post.deleted_with_topic'))
          expect(Frm::Topic.count).to eq 0
          expect(Frm::Post.count).to eq 0
        end
      end
    end
  end
end
