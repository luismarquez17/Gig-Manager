module Users
  class RegistrationsController < Devise::RegistrationsController
    def new
      marquez_company = Company.find_by(slug: 'marquez-musica') || Company.first
      if marquez_company.present?
        redirect_to join_company_path(marquez_company.slug), notice: "El registro directo no está habilitado. Has sido redirigido al registro oficial de #{marquez_company.name}."
      else
        redirect_to root_path, alert: "El registro público está restringido. Utiliza un enlace de invitación oficial."
      end
    end

    def create
      marquez_company = Company.find_by(slug: 'marquez-musica') || Company.first
      if marquez_company.present?
        redirect_to join_company_path(marquez_company.slug)
      else
        redirect_to root_path, alert: "El registro público está restringido."
      end
    end
  end
end
