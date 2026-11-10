defmodule Emergencias.Permisos do
  @moduledoc """
  Restricción de operaciones por tipo de usuario.

  Cada rol hereda los permisos del anterior; la herencia se construye uniendo
  MapSet (ciudadano ⊂ voluntario ⊂ coordinador ⊂ administrador). Consultar un
  permiso es una pregunta de pertenencia, justo lo que MapSet resuelve bien.
  """

  @ciudadano MapSet.new([
               :report_person,
               :find_person,
               :search_persons,
               :person_history,
               :send_family_message,
               :list_family_messages,
               :report_pet,
               :list_pets,
               :register_need,
               :list_needs,
               :check_shelter,
               :shelters_available,
               :availability,
               :list_zones,
               :zone_status,
               :activity
             ])

  @voluntario MapSet.union(
                @ciudadano,
                MapSet.new([
                  :update_person,
                  :mark_message,
                  :match_pets,
                  :confirm_match,
                  :register_entry,
                  :register_exit,
                  :resource_in,
                  :resource_out,
                  :attend_need,
                  :list_resources,
                  :resource_history,
                  :list_shelters
                ])
              )

  @coordinador MapSet.union(
                 @voluntario,
                 MapSet.new([
                   :register_zone,
                   :register_sector,
                   :register_point,
                   :update_zone,
                   :zone_stats,
                   :register_resource,
                   :assign_resource,
                   :transfer_resource,
                   :critical_resources,
                   :register_shelter,
                   :shelter_report,
                   :close_need,
                   :cancel_need,
                   :pending_needs,
                   :dispatch_needs,
                   :summary,
                   :simulate_conflict,
                   :load_demo
                 ])
               )

  @administrador MapSet.union(@coordinador, MapSet.new([:list_users, :set_role, :activity_all]))

  @por_rol %{
    ciudadano: @ciudadano,
    voluntario: @voluntario,
    coordinador: @coordinador,
    administrador: @administrador
  }

  def permisos(rol), do: Map.get(@por_rol, rol, MapSet.new())

  def permitido?(rol, accion), do: rol |> permisos() |> MapSet.member?(accion)

  @doc "`:ok` o `{:error, {:sin_permiso, accion, rol}}`."
  def autorizar(%{tipo: rol}, accion), do: autorizar(rol, accion)

  def autorizar(rol, accion) when is_atom(rol) do
    if permitido?(rol, accion), do: :ok, else: {:error, {:sin_permiso, accion, rol}}
  end
end
