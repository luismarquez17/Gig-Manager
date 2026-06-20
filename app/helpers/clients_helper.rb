module ClientsHelper
  def color_prioridad(prioridad)
    case prioridad
    when 'alta'  then 'green'
    when 'media' then 'orange'
    when 'baja'  then 'red'
    else 'black'
    end
  end
end