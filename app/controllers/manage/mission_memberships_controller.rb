class Manage::MissionMembershipsController < Manage::BaseController
  before_action :set_membership, only: [ :update, :destroy ]

  # Managers can only add reviewers. Assigning owners is an admin-only action
  # — Admin::MissionMembershipsController handles that.
  def create
    user = User.find_by(id: membership_params[:user_id])
    user ||= User.find_by(slack_id: membership_params[:user_id])

    if user.nil?
      redirect_to edit_manage_mission_path(@mission.slug), alert: "User not found." and return
    end

    membership = @mission.memberships.new(user: user, role: :reviewer)
    if membership.save
      redirect_to edit_manage_mission_path(@mission.slug), notice: "Reviewer added."
    else
      redirect_to edit_manage_mission_path(@mission.slug), alert: membership.errors.full_messages.to_sentence
    end
  end

  def update
    # Reserved for future use (e.g., toggling reviewer permissions). For now,
    # managers can't change roles at all — owners are admin-only territory.
    redirect_to edit_manage_mission_path(@mission.slug), alert: "Role changes are admin-only."
  end

  def destroy
    if @membership.owner_role?
      redirect_to edit_manage_mission_path(@mission.slug),
                  alert: "Removing owners is admin-only — head to the admin page." and return
    end

    @membership.destroy!
    redirect_to edit_manage_mission_path(@mission.slug), notice: "Reviewer removed."
  end

  private

  def set_membership
    @membership = @mission.memberships.find(params[:id])
  end

  def membership_params
    params.require(:mission_membership).permit(:user_id)
  end
end
