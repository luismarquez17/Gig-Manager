module TenantScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :company, optional: true

    scope :for_company, ->(company) { where(company: company) }
    scope :current_tenant, -> { where(company: Current.company) if Current.company.present? }

    before_validation :assign_current_company, on: :create
  end

  private

  def assign_current_company
    self.company ||= Current.company || Company.first
  end
end
