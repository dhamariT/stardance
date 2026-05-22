module Reviewer
  class ShipsController < Reviewer::ApplicationController
    before_action :release_other_claims, only: [ :index, :next, :claim ]
    before_action :set_ship_review, only: [ :show, :update, :claim ]

    def index
      authorize ShipReview
      @reviews = policy_scope(ShipReview)
                   .pending
                   .includes(:project, :reviewer)
                   .order(claim_expires_at: :asc, created_at: :asc)
                   .limit(50)
    end

    def show
      authorize @ship_review
    end

    def update
      authorize @ship_review
      if @ship_review.update(ship_review_params)
        redirect_to next_reviewer_ships_path, notice: "Verdict recorded."
      else
        render :show, status: :unprocessable_entity
      end
    end

    def next
      authorize ShipReview
      skip_ids = parse_skip_ids
      candidate = ShipReview.next_eligible(current_user, skip_ids: skip_ids)
      if candidate.nil?
        redirect_to reviewer_ships_path, notice: "Queue is empty." and return
      end
      claimed = ShipReview.atomic_claim!(candidate.id, current_user)
      if claimed
        redirect_to reviewer_ship_path(claimed)
      else
        new_skip = (skip_ids + [ candidate.id ]).uniq
        redirect_to next_reviewer_ships_path(skip: new_skip.join(","))
      end
    end

    def claim
      authorize @ship_review, :claim?
      claimed = ShipReview.atomic_claim!(@ship_review.id, current_user)
      if claimed
        redirect_to reviewer_ship_path(claimed)
      else
        redirect_to reviewer_ships_path, alert: "Couldn't claim that review — someone else got it."
      end
    end

    private

    def set_ship_review
      @ship_review = ShipReview.find(params[:id])
    end

    def release_other_claims
      ShipReview.release_all_for(current_user) if current_user.present?
    end

    def parse_skip_ids
      params[:skip].to_s.split(",").map(&:to_i).reject(&:zero?)
    end

    def ship_review_params
      params.require(:ship_review).permit(:status, :feedback, :internal_reason)
    end
  end
end
