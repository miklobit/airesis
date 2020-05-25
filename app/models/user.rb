require 'digest/sha1'

class User < ActiveRecord::Base
  acts_as_token_authenticatable

  devise :database_authenticatable, :registerable, :confirmable, :omniauthable,
         :blockable, :recoverable, :rememberable, :trackable, :validatable, :traceable

  include TutorialAssigneesHelper

  attr_accessor :image_url, :accept_conditions, :accept_privacy, :interest_borders_tokens

  validates_presence_of :name
  validates_format_of :name, with: AuthenticationModule.name_regex, allow_nil: true
  validates_length_of :name, maximum: 50

  validates_format_of :surname, with: AuthenticationModule.name_regex, allow_nil: true
  validates_length_of :surname, maximum: 50

  validates_confirmation_of :password

  validates_acceptance_of :accept_conditions, message: I18n.t('activerecord.errors.messages.TOS')
  validates_acceptance_of :accept_privacy, message: I18n.t('activerecord.errors.messages.privacy')

  has_many :proposal_presentations, inverse_of: :user, dependent: :destroy # TODO: replace with anonymous user
  has_many :proposals, through: :proposal_presentations, class_name: 'Proposal', inverse_of: :users
  has_many :notifications, through: :alerts, class_name: 'Notification'
  has_many :meeting_participations, dependent: :destroy
  has_one :blog, inverse_of: :user, dependent: :destroy
  has_many :blog_comments, inverse_of: :user, dependent: :destroy
  has_many :blog_posts, inverse_of: :user, dependent: :destroy
  has_many :blocked_alerts, inverse_of: :user, dependent: :destroy
  has_many :blocked_emails, inverse_of: :user, dependent: :destroy

  has_many :event_comments, dependent: :destroy, inverse_of: :user
  has_many :likes, class_name: 'EventCommentLike', dependent: :destroy, inverse_of: :user

  has_many :group_participations, dependent: :destroy, inverse_of: :user
  has_many :groups, through: :group_participations, class_name: 'Group'
  has_many :portavoce_groups, -> { joins(' INNER JOIN participation_roles ON participation_roles.id = group_participations.participation_role_id').where("(participation_roles.name = 'amministratore')") }, through: :group_participations, class_name: 'Group', source: 'group'

  has_many :area_participations, class_name: 'AreaParticipation', inverse_of: :user
  has_many :group_areas, through: :area_participations, class_name: 'GroupArea'

  has_many :participation_roles, through: :group_participations, class_name: 'ParticipationRole', inverse_of: :user
  has_many :group_follows, class_name: 'GroupFollow', inverse_of: :user
  has_many :followed_groups, through: :group_follows, class_name: 'Group', source: :group
  has_many :user_votes, class_name: 'UserVote', inverse_of: :user
  has_many :proposal_comments, class_name: 'ProposalComment', inverse_of: :user
  has_many :partecipating_proposals, through: :proposal_comments, class_name: 'Proposal', source: :proposal
  has_many :proposal_comment_rankings, class_name: 'ProposalCommentRanking'
  has_many :proposal_rankings, class_name: 'ProposalRanking'
  has_many :proposal_revisions, inverse_of: :user
  belongs_to :image, class_name: 'Image', foreign_key: :image_id, optional: true
  has_many :authentications, class_name: 'Authentication', dependent: :destroy

  has_many :user_borders, class_name: 'UserBorder'

  # confini di interesse
  has_many :interest_borders, through: :user_borders, class_name: 'InterestBorder'

  has_many :alerts, -> { order('alerts.created_at DESC') }, class_name: 'Alert'
  has_many :unread_alerts, -> { where 'alerts.checked = false' }, class_name: 'Alert'

  has_many :blocked_notifications, through: :blocked_alerts, class_name: 'NotificationType', source: :notification_type
  has_many :blocked_email_notifications, through: :blocked_emails, class_name: 'NotificationType', source: :notification_type

  has_many :group_participation_requests, dependent: :destroy

  has_many :followers_user_follow, class_name: 'UserFollow', foreign_key: :followed_id
  has_many :followers, through: :followers_user_follow, class_name: 'User', source: :followed

  has_many :followed_user_follow, class_name: 'UserFollow', foreign_key: :follower_id
  has_many :followed, through: :followed_user_follow, class_name: 'User', source: :follower

  has_many :tutorial_assignees, dependent: :destroy
  has_many :tutorials, through: :tutorial_assignees, class_name: 'Tutorial', source: :tutorial

  has_many :tutorial_progresses, dependent: :destroy
  has_many :todo_tutorial_assignees, -> { where('tutorial_assignees.completed = false') }, class_name: 'TutorialAssignee'
  has_many :todo_tutorials, through: :todo_tutorial_assignees, class_name: 'Tutorial', source: :tutorial

  belongs_to :locale, class_name: 'SysLocale', inverse_of: :users, foreign_key: 'sys_locale_id'
  belongs_to :original_locale, class_name: 'SysLocale', inverse_of: :original_users, foreign_key: 'original_sys_locale_id'

  has_many :events

  has_many :proposal_nicknames, dependent: :destroy

  # forum
  has_many :viewed, class_name: 'Frm::View'
  has_many :viewed_topics, class_name: 'Frm::Topic', through: :viewed, source: :viewable, source_type: 'Frm::Topic'
  has_many :unread_topics, -> { where 'frm_views.updated_at < frm_topics.last_post_at' }, class_name: 'Frm::Topic', through: :viewed, source: :viewable, source_type: 'Frm::Topic'
  has_many :memberships, class_name: 'Frm::Membership', inverse_of: :member, foreign_key: :member_id
  has_many :frm_mods, through: :memberships, class_name: 'Frm::Mod', source: :mod

  before_create :init
  after_create :assign_tutorials

  before_update :before_update_populate

  enum user_type_id: { administrator: 1, moderator: 2, authenticated: 3 }, _prefix: true

  # Check for paperclip
  has_attached_file :avatar,
                    styles: {
                      thumb: '100x100#',
                      small: '150x150>'
                    },
                    path: (Paperclip::Attachment.default_options[:storage] == :s3) ?
                      'avatars/:id/:style/:basename.:extension' : ':rails_root/public:url'

  validates_attachment_size :avatar, less_than: UPLOAD_LIMIT_IMAGES.bytes
  validates_attachment_content_type :avatar, content_type: ['image/jpeg', 'image/png', 'image/gif', 'image/jpg']

  scope :all_except, ->(user) { where.not(id: user) }

  scope :blocked, -> { where(blocked: true) }
  scope :unblocked, -> { where(blocked: false) }
  scope :confirmed, -> { where 'confirmed_at is not null' }
  scope :unconfirmed, -> { where 'confirmed_at is null' }
  scope :count_active, -> { unblocked.count.to_f * (ENV['ACTIVE_USERS_PERCENTAGE'].to_f / 100.0) }

  scope :autocomplete, ->(term) { where('lower(users.name) LIKE :term or lower(users.surname) LIKE :term', term: "%#{term.to_s.downcase}%").order('users.surname desc, users.name desc').limit(10) }
  scope :non_blocking_notification, lambda { |notification_type|
    User.where.not(id: User.select('users.id').
      joins(:blocked_alerts).
      where(blocked_alerts: { notification_type_id: notification_type }))
  }
  scope :by_interest_borders, ->(ib) { where('users.derived_interest_borders_tokens @> ARRAY[?]::varchar[]', ib) }

  def avatar_url=(url)
    file = URI.parse(url)
    self.avatar = file
  rescue
    # ignored
  end

  def suggested_groups
    border = interest_borders.first
    params = {}
    params[:interest_border_obj] = border
    params[:limit] = 12
    Group.look(params)
  end

  def email_required?
    super && !has_oauth_provider_without_email
  end

  def last_proposal_comment
    proposal_comments.order('created_at desc').first
  end

  # dopo aver creato un nuovo utente gli assegno il primo tutorial e
  # disattivo le notifiche standard
  def assign_tutorials
    Tutorial.all.each do |tutorial|
      assign_tutorial(self, tutorial)
    end
    GeocodeUser.perform_in(5.seconds, id)
  end

  def init
    self.rank ||= 0 # imposta il rank a zero se non è valorizzato
    self.receive_messages = true
    self.receive_newsletter = true
    update_borders
    blocked_alerts.build(notification_type_id: NotificationType::NEW_VALUTATION_MINE)
    blocked_alerts.build(notification_type_id: NotificationType::NEW_VALUTATION)
    blocked_alerts.build(notification_type_id: NotificationType::NEW_PUBLIC_EVENTS)
    blocked_alerts.build(notification_type_id: NotificationType::NEW_PUBLIC_PROPOSALS)
  end

  # geocode user setting his default time zone
  def geocode
    @search = Geocoder.search(last_sign_in_ip)
    unless @search.empty? # continue only if we found latitude and longitude
      @latlon = [@search[0].latitude, @search[0].longitude]
      @zone = Timezone::Zone.new latlon: @latlon rescue nil # if we can't find the latitude and longitude zone just set zone to nil
      update(time_zone: @zone.active_support_time_zone) if @zone # update zone if found
    end
  end

  # restituisce l'elenco delle partecipazioni ai gruppi dell'utente
  # all'interno dei quali possiede un determinato permesso
  def scoped_group_participations(abilitation)
    group_participations.
      joins(' INNER JOIN participation_roles ON participation_roles.id = group_participations.participation_role_id').
      where("participation_roles.name = 'amministratore' OR participation_roles.#{abilitation} = true")
  end

  # restituisce l'elenco dei gruppi dell'utente
  # all'interno dei quali possiede un determinato permesso
  def scoped_groups(abilitation, excluded_groups = nil)
    ret = groups.
      joins(' INNER JOIN participation_roles ON participation_roles.id = group_participations.participation_role_id').
      where("(participation_roles.name = 'amministratore' OR participation_roles.#{abilitation} = true")
    excluded_groups ? ret - excluded_groups : ret
  end

  # return all group area participations of a particular group where the user can do a particular action or
  # all group areas of the user in a group if abilitation_id is null
  def scoped_areas(group_id, abilitation_id = nil)
    group = Group.find(group_id)
    ret = nil
    if group.portavoce.include? self
      ret = group.group_areas
    elsif abilitation_id
      ret = group_areas.joins(:area_roles).
        where(["group_areas.group_id = ? AND area_roles.#{abilitation_id} = true AND area_participations.area_role_id = area_roles.id", group_id]).
        distinct
    else
      ret = group_areas.joins(:area_roles).
        where(['group_areas.group_id = ?', group_id]).distinct
    end
    ret
  end

  def self.new_with_session(params, session)
    super.tap do |user|
      user.last_sign_in_ip = session[:remote_ip]
      user.original_sys_locale_id = user.sys_locale_id = SysLocale.default.id

      oauth_data = session['devise.omniauth_data']
      user_info = OauthDataParser.new(oauth_data).user_info if oauth_data

      if user_info
        user.email = user_info[:email]
      elsif (data = session[:user]) # what does it do? can't remember
        user.email = session[:user][:email]
        if invite = session[:invite] # if is by invitation
          group_invitation_email = GroupInvitationEmail.find_by(token: invite[:token])
          user.skip_confirmation! if user.email == group_invitation_email.email
        end
      end
    end
  end

  def last_blog_comment
    blog_comments
  end

  def encoded_id
    Base64.encode64(id)
  end

  def self.decode_id(id)
    Base64.decode64(id)
  end

  def image_url
    avatar.url
  end

  # determina se un oggetto appartiene all'utente verificando che
  # l'oggetto abbia un campo user_id corrispondente all'id dell'utente
  # in caso contrario verifica se l'oggetto ha un elenco di utenti collegati
  # e proprietari, in caso affermativo verifica di rientrare tra questi.
  def is_mine?(object)
    if object
      if object.respond_to?('user_id')
        return object.user_id == id
      elsif object.respond_to?('users')
        return object.users.find_by_id(id)
      else
        return false
      end
    else
      return false
    end
  end

  # questo metodo prende in input l'id di una proposta e verifica che l'utente ne sia l'autore
  def is_my_proposal?(proposal_id)
    proposal = proposals.find_by_id(proposal_id) # cerca tra le mie proposte quella con id 'proposal_id'
    if proposal # se l'ho trovata allora è mia
      true
    else
      false
    end
  end

  # questo metodo prende in input l'id di una proposta e verifica che l'utente ne sia l'autore
  def is_my_blog_post?(blog_post_id)
    blog_post = blog_posts.find_by_id(blog_post_id) # cerca tra le mie proposte quella con id 'proposal_id'
    if blog_post # se l'ho trovata allora è mia
      true
    else
      false
    end
  end

  # questo metodo prende in input l'id di un blog e verifica che appartenga all'utente
  def is_my_blog?(blog_id)
    if blog && blog.id == blog_id
      true
    else
      false
    end
  end

  def has_ranked_proposal?(proposal_id)
    ProposalRanking.where(user_id: id, proposal_id: proposal_id).exists?
  end

  # restituisce il voto che l'utente ha dato ad un determinato commento
  # se l'ha dato. nil altrimenti
  def comment_rank(comment)
    ranking = ProposalCommentRanking.find_by(user_id: id, proposal_comment_id: comment.id)
    ranking.try(:ranking_type_id)
  end

  # restituisce true se l'utente ha valutato un contributo
  # ma è stato successivamente inserito un commento e può quindi valutarlo di nuovo oppure il contributo è stato modificato
  def can_rank_again_comment?(comment)
    # return false unless comment.proposal.in_valutation? #can't change opinion if not in valutation anymore
    ranking = ProposalCommentRanking.find_by_user_id_and_proposal_comment_id(id, comment.id)
    return true unless ranking # si, se non l'ho mai valutato
    return true if ranking.updated_at < comment.updated_at # si, se è stato aggiornato dopo la mia valutazione
    last_suggest = comment.replies.order('created_at desc').first
    return false unless last_suggest # no, se non vi è alcun commento
    ranking.updated_at < last_suggest.created_at # si, se vi sono commenti dopo la mia valutazione
  end

  def admin?
    user_type_id_administrator?
  end

  def moderator?
    admin? || user_type_id_moderator?
  end

  # restituisce la richiesta di partecipazione
  def has_asked_for_participation?(group_id)
    group_participation_requests.find_by(group_id: group_id)
  end

  def fullname
    "#{name} #{surname}"
  end

  def to_param
    "#{id}-#{fullname.downcase.gsub(/[^a-zA-Z0-9]+/, '-').gsub(/-{2,}/, '-').gsub(/^-|-$/, '')}"
  end

  delegate :can?, :cannot?, to: :ability

  def ability
    @ability ||= Ability.new(self)
  end

  def can_read_forem_category?(category)
    category.visible_outside || (category.group.participants.include? self)
  end

  def can_read_forem_forum?(forum)
    forum.visible_outside || (forum.group.participants.include? self)
  end

  def can_create_forem_topics?(forum)
    forum.group.participants.include? self
  end

  def can_reply_to_forem_topic?(topic)
    topic.forum.group.participants.include? self
  end

  def can_edit_forem_posts?(forum)
    forum.group.participants.include? self
  end

  def can_read_forem_topic?(topic)
    !topic.hidden? || forem_admin?(topic.forum.group) || (topic.user == self)
  end

  def can_moderate_forem_forum?(forum)
    forum.moderator?(self)
  end

  def forem_admin?(group)
    self.can? :update, group
  end

  def to_s
    fullname
  end

  def user_image_url(size = 80, _params = {})
    if self.respond_to?(:user)
      user = self.user
    else
      user = self
    end

    if user.avatar.file?
      user.avatar.url
    else
      # Gravatar
      require 'digest/md5'
      if !user.email.blank?
        email = user.email
      else
        return ''
      end

      hash = Digest::MD5.hexdigest(email.downcase)
      "https://www.gravatar.com/avatar/#{hash}?s=#{size}"
    end
  end

  # authentication method
  def has_provider?(provider_name)
    authentications.find_by(provider: provider_name).present?
  end

  def from_identity_provider?
    authentications.any?
  end

  def build_authentication_provider(access_token)
    authentications.build(provider: access_token['provider'], uid: access_token['uid'], token: (access_token['credentials']['token'] rescue nil))
  end

  def facebook
    @fb_user ||= Koala::Facebook::API.new(authentications.find_by(provider: Authentication::FACEBOOK).token) rescue nil
  end

  # return the user, a flag indicating if it's the first time the oauth account
  # is associated to the Airesis account or if it's a simple login and another flag
  # indicating if the user has been found in th db by it's email
  def self.find_or_create_for_oauth_provider(oauth_data)
    oauth_data_parser = OauthDataParser.new(oauth_data)
    provider = oauth_data_parser.provider
    uid = oauth_data_parser.uid
    user_info = oauth_data_parser.user_info

    # se ho trovato l'id dell'utente prendi lui, altrimenti cercane uno con l'email uguale
    auth = Authentication.find_by(provider: provider, uid: uid)
    if auth
      # return user, first_association, found_from_email
      return auth.user, false, false
    else
      user = user_info[:email] && User.find_by(email: user_info[:email])
      # return user, first_association, found_from_email
      return user ? [user, true, true] : [create_account_for_oauth(oauth_data), true, false]
    end
  end

  def oauth_join(oauth_data)
    oauth_data_parser = OauthDataParser.new(oauth_data)
    provider = oauth_data_parser.provider
    raw_info = oauth_data_parser.raw_info
    user_info = oauth_data_parser.user_info

    User.transaction do
      build_authentication_provider(oauth_data)

      self.email = user_info[:email] unless email
      set_social_network_pages(provider, raw_info)

      save!
    end
  end

  def set_social_network_pages(provider, raw_info)
    self.google_page_url = raw_info['profile'] if provider == Authentication::GOOGLE
    self.facebook_page_url = raw_info['link'] if provider == Authentication::FACEBOOK
  end

  def twitter_page_url
    "https://twitter.com/intent/user?user_id=#{authentications.find_by(provider: Authentication::TWITTER).uid}"
  end

  def send_reset_password_instructions
    if blocked
      errors.add(:base, :not_found)
      return false
    end
    super
  end

  protected

  def reconfirmation_required?
    self.class.reconfirmable && @reconfirmation_required
  end

  def self.create_account_for_oauth(oauth_data)
    oauth_data_parser = OauthDataParser.new(oauth_data)
    provider = oauth_data_parser.provider
    raw_info = oauth_data_parser.raw_info
    user_info = oauth_data_parser.user_info

    # Not enough info from oauth provider
    return nil if user_info[:name].blank?

    user = User.new(name: user_info[:name],
                    surname: user_info[:surname],
                    password: Devise.friendly_token[0, 20],
                    sex: user_info[:sex],
                    email: user_info[:email])

    user.tap do |user|
      user.avatar_url = user_info[:avatar_url]

      user.google_page_url = raw_info['profile'] if provider == Authentication::GOOGLE
      user.facebook_page_url = raw_info['link'] if provider == Authentication::FACEBOOK

      User.transaction do
        user.build_authentication_provider(oauth_data)

        user.sign_in_count = 0
        user.confirm
        user.user_type_id = :authenticated
        user.save!
      end
    end
  end

  def has_oauth_provider_without_email
    has_provider?(Authentication::TWITTER)
  end

  def before_create_populate
  end

  def before_update_populate
    user_borders.destroy_all
    update_borders
  end

  def update_borders
    return unless interest_borders_tokens
    interest_borders_tokens.split(',').each do |border|
      ftype = border[0, 1]
      fid = border[2..-1]
      found = InterestBorder.table_element(border)
      next unless found

      derived_row = found
      while derived_row
        self.derived_interest_borders_tokens |= [InterestBorder.to_key(derived_row)]
        derived_row = derived_row.parent
      end

      interest_b = InterestBorder.find_or_create_by(territory_type: InterestBorder::I_TYPE_MAP[ftype],
                                                    territory_id: fid)
      user_borders.build(interest_border_id: interest_b.id)
    end
  end
end
