module Admin
  # Owner-only membership management. Reviewers are handled on the manage
  # side via Manage::MissionMembershipsController. Admins still have access
  # to the manage page (per MissionPolicy#manage?), so they can edit
  # reviewers there too — this controller's job is the bit managers can't do.
  class MissionMembershipsController < Admin::ApplicationController
    layout "application"

    before_action :set_mission
    before_action :authorize_mission_update
    before_action :set_membership, only: [ :destroy ]

    def create
      user = User.find_by(id: membership_params[:user_id])
      user ||= User.find_by(slack_id: membership_params[:user_id])

      if user.nil?
        redirect_to edit_admin_mission_path(@mission.slug), alert: "User not found." and return
      end

      membership = @mission.memberships.new(user: user, role: :owner)
      if membership.save
        redirect_to edit_admin_mission_path(@mission.slug), notice: "Owner added."
      else
        redirect_to edit_admin_mission_path(@mission.slug), alert: membership.errors.full_messages.to_sentence
      end
    end

    def destroy
      unless @membership.owner_role?
        redirect_to edit_admin_mission_path(@mission.slug),
                    alert: "Use the manage page to remove a reviewer." and return
      end

      remaining = @mission.memberships
                          .where(role: Mission::Membership.roles[:owner])
                          .where.not(id: @membership.id)
                          .count
      if remaining.zero?
        redirect_to edit_admin_mission_path(@mission.slug),
                    alert: "Can't remove the last owner — assign another owner first." and return
      end

      @membership.destroy!
      redirect_to edit_admin_mission_path(@mission.slug), notice: "Owner removed."
    end

    private

    def set_mission
      @mission = Mission.find_by!(slug: params[:mission_slug])
    end

    def authorize_mission_update
      authorize @mission, :update?
    end

    def set_membership
      @membership = @mission.memberships.find(params[:id])
    end

    def membership_params
      params.require(:mission_membership).permit(:user_id)
    end
  end
end
