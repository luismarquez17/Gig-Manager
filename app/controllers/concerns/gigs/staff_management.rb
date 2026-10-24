# frozen_string_literal: true

module Gigs
  module StaffManagement
    extend ActiveSupport::Concern

    def assign_staff
      user = if params[:staff_id].present?
               current_company.users.find_by(id: params[:staff_id])
             elsif params[:new_eventual_worker_name].present?
               User.create_eventual_worker!(
                 company: current_company,
                 name: params[:new_eventual_worker_name],
                 role: params[:new_eventual_worker_role].presence || 'staff',
                 phone: params[:new_eventual_worker_phone].presence,
                 specialty: params[:new_eventual_worker_specialty].presence
               )
             end

      raw_agreed = if params[:new_eventual_worker_name].present?
                     params[:eventual_agreed_amount].presence || params[:agreed_amount]
                   else
                     params[:agreed_amount].presence || params[:eventual_agreed_amount]
                   end
      agreed_amount = raw_agreed.to_s.tr(',', '.').strip.to_f

      if user && (user.staff? || user.leader? || user.musician?)
        assignment = @gig.staff_assignments.find_or_initialize_by(user_id: user.id)
        is_new = assignment.new_record?
        previous_amount = assignment.agreed_amount.to_f
        assignment.agreed_amount = agreed_amount
        assignment.save!

        target_area = user.musician? ? 'musicians' : 'staffs'
        date_formatted = @gig.date ? @gig.date.strftime("%d/%m/%Y") : "próximamente"
        client_name = @gig.client&.name || "Cliente"

        if is_new && !user.eventual?
          # Notificar al músico / staff asignado (únicamente a este usuario)
          AppNotification.create(
            company: @gig.company,
            sender: current_user,
            recipient: user,
            target_area: target_area,
            notification_type: 'gig_alert',
            title: "🎸 Has sido asignado a un evento",
            message: "Fuiste asignado al show de '#{client_name}' para la fecha #{date_formatted} en #{@gig.location.presence || 'Ubicación por confirmar'}.",
            action_url: "/my_gigs"
          ) rescue nil
        end

        if is_new
          # Notificar al área de líderes
          eventual_tag = user.eventual? ? " (Trabajador Eventual)" : ""
          AppNotification.create(
            company: @gig.company,
            sender: current_user,
            target_area: 'leaders',
            notification_type: 'gig_alert',
            title: "👤 Nueva Asignación de Personal",
            message: "#{user.display_name}#{eventual_tag} ha sido asignado(a) al show '#{client_name}' (#{date_formatted}).",
            action_url: "/gigs/#{@gig.id}"
          ) rescue nil
        elsif (agreed_amount - previous_amount).abs > 0.01 && !user.eventual?
          # Notificar al trabajador si se actualizó el pago acordado
          AppNotification.create(
            company: @gig.company,
            sender: current_user,
            recipient: user,
            target_area: target_area,
            notification_type: 'payment_alert',
            title: "💰 Actualización de Pago Acordado",
            message: "Se actualizó tu pago acordado a $#{view_context.number_with_precision(agreed_amount, precision: 2)} en el show de '#{client_name}' (#{date_formatted}).",
            action_url: "/my_payments"
          ) rescue nil
        end

        prefix = user.eventual? ? "⚡ Trabajador eventual " : "Trabajador "
        notice_msg = is_new ? "#{prefix}'#{user.display_name}' asignado con éxito con pago acordado de $#{view_context.number_with_precision(agreed_amount, precision: 2)}." : "Pago acordado para #{user.display_name} actualizado."
        redirect_to gig_path(@gig), notice: notice_msg
      else
        redirect_to gig_path(@gig), alert: "Debes seleccionar o ingresar un trabajador válido."
      end
    end

    def remove_staff
      user = current_company.users.find_by(id: params[:staff_id])
      assignment = @gig.staff_assignments.find_by(user_id: user&.id)

      if assignment
        assignment.destroy
        redirect_to gig_path(@gig), notice: "Trabajador desasignado del show."
      else
        redirect_to gig_path(@gig), alert: "Asignación no encontrada."
      end
    end

    def update_staff_pay
      assignment = @gig.staff_assignments.find_by(id: params[:staff_assignment_id])
      agreed_amount = params[:agreed_amount].to_s.tr(',', '.').to_f

      if assignment
        assignment.update!(agreed_amount: agreed_amount)

        date_formatted = @gig.date ? @gig.date.strftime("%d/%m/%Y") : "próximamente"
        client_name = @gig.client&.name || "Cliente"
        target_area = assignment.user.musician? ? 'musicians' : 'staffs'

        AppNotification.create(
          company: @gig.company,
          sender: current_user,
          recipient: assignment.user,
          target_area: target_area,
          notification_type: 'payment_alert',
          title: "💰 Actualización de Pago Acordado",
          message: "Se actualizó tu pago acordado a $#{view_context.number_with_precision(agreed_amount, precision: 2)} en el show de '#{client_name}' (#{date_formatted}).",
          action_url: "/my_payments"
        ) rescue nil

        redirect_to gig_path(@gig), notice: "Pago acordado para #{assignment.user.display_name} actualizado a $#{view_context.number_with_precision(agreed_amount, precision: 2)}."
      else
        redirect_to gig_path(@gig), alert: "Asignación no encontrada."
      end
    end
  end
end
