# The {ActivityObject} is any object that receives actions. Examples are
# creating post, liking a comment, contacting a user. 
#
# = ActivityObject subtypes
# All post, comment and user are {SocialStream::Models::Object objects}.
# Social Stream privides 3 {ActivityObject} subtypes, {Post}, {Comment} and
# {Actor}. The application developer can define as many {ActivityObject} subtypes
# as required.
# Objects are added to +config/initializers/social_stream.rb+
#
class ActivityObject < ActiveRecord::Base
  attr_writer :_relation_ids
  attr_reader :_activity_parent_id

  # See {SocialStream::Models::Channeled}
  channeled

  # ActivityObject is a supertype of SocialStream.objects
  supertype_of :object

  acts_as_taggable

  has_many :activity_object_activities, :dependent => :destroy
  has_many :activities, :through => :activity_object_activities

  has_many :received_actions,
           :class_name => "ActivityAction",
           :dependent  => :destroy
  has_many :followers,
           :through => :received_actions,
           :source  => :actor,
           :conditions => { 'activity_actions.follow' => true }

  has_many :activity_object_properties,
           :dependent => :destroy
  has_many :object_properties,
           :through => :activity_object_properties,
           :source => :property
  has_many :activity_object_holders,
           :class_name  => "ActivityObjectProperty",
           :foreign_key => :property_id,
           :dependent   => :destroy
  has_many :object_holders,
           :through => :activity_object_holders,
           :source  => :activity_object

  validates_presence_of :object_type

  # TODO: This is currently defined in lib/social_stream/models/object.rb
  #
  # Need to fix activity_object_spec_helper before activating it
  #
  # validates_presence_of :author_id, :owner_id, :user_author_id, :unless => :acts_as_actor?
  # after_create :create_post_activity, :unless => :acts_as_actor?

  scope :authored_by, lambda { |subject|
    joins(:channel).merge(Channel.authored_by(subject))
  }

  # The object of this activity object
  def object
    subtype_instance.is_a?(Actor) ?
      subtype_instance.subject :
      subtype_instance
  end

  # Does this {ActivityObject} has {Actor}?
  def acts_as_actor?
    object_type == "Actor"
  end

  def actor!
    actor || raise("Unknown Actor for ActivityObject: #{ inspect }")
  end

  # Return the {Action} model to an {Actor}
  def action_from(actor)
    received_actions.sent_by(actor).first
  end

  # The activity in which this activity_object was created
  def post_activity
    activities.includes(:activity_verb).where('activity_verbs.name' => 'post').first
  end

  # Build the post activity when this object is not saved
  def build_post_activity
    Activity.new :channel      => channel!,
                 :relation_ids => Array(_relation_ids)
  end

  def _relation_ids
    @_relation_ids ||=
      if channel!.author.blank? || channel!.owner.blank?
        nil
      else
        # FIXME: repeated in Activity#fill_relations
        if SocialStream.relation_model == :custom
          if channel!.reflexive?
            channel!.owner.relation_customs.map(&:id)
          else
            channel!.
              owner.
              relation_customs.
              allow(channel.author, 'create', 'activity').
              map(&:id)
          end
        else
          Array.wrap Relation::Public.instance.id
        end
      end
  end

  def _activity_parent
    @_activity_parent ||= Activity.find(_activity_parent_id)
  end

  def _activity_parent_id=(id)
    self._relation_ids = Activity.find(id).relation_ids
    @_activity_parent_id = id
  end

  private

  def create_post_activity
    create_activity "post"
  end

  def create_update_activity
    create_activity "update"
  end

  def create_activity(verb)
    a = Activity.new :verb         => verb,
      :channel      => channel,
      :relation_ids => _relation_ids,
      :parent_id    => _activity_parent_id

    a.activity_objects << self

    a.save!
  end
end
