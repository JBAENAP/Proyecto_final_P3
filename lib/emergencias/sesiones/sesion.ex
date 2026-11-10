defmodule Emergencias.Sesiones.Sesion do
  @moduledoc """
  Proceso de sesión de un usuario conectado. Se crea en `connect` bajo el
  DynamicSupervisor y termina en `disconnect`.

  Se registra en `Emergencias.RegistroSesiones` con el username como clave, por
  eso un mismo usuario no puede tener dos sesiones abiertas a la vez. Además
  monitorea al proceso cliente (la consola): si el cliente muere, la sesión se
  cierra sola y el usuario queda desconectado.
  """

  use GenServer, restart: :temporary

  def start_link({usuario, cliente}) do
    GenServer.start_link(__MODULE__, {usuario, cliente}, name: via(usuario.username))
  end

  def via(username), do: {:via, Registry, {Emergencias.RegistroSesiones, username}}

  def usuario(sesion), do: GenServer.call(sesion, :usuario)
  def info(sesion), do: GenServer.call(sesion, :info)
  def contar_comando(sesion), do: GenServer.cast(sesion, :comando)
  def actualizar_usuario(sesion, usuario), do: GenServer.cast(sesion, {:usuario, usuario})
  def cerrar(sesion), do: GenServer.stop(sesion, :normal)

  @impl true
  def init({usuario, cliente}) do
    Process.monitor(cliente)

    {:ok,
     %{
       usuario: usuario,
       cliente: cliente,
       conectado_en: Emergencias.Persistencia.ahora(),
       comandos: 0
     }}
  end

  @impl true
  def handle_call(:usuario, _de, estado), do: {:reply, estado.usuario, estado}
  def handle_call(:info, _de, estado), do: {:reply, estado, estado}

  @impl true
  def handle_cast(:comando, estado), do: {:noreply, %{estado | comandos: estado.comandos + 1}}
  def handle_cast({:usuario, usuario}, estado), do: {:noreply, %{estado | usuario: usuario}}

  @impl true
  def handle_info({:DOWN, _ref, :process, cliente, _motivo}, %{cliente: cliente} = estado) do
    Emergencias.Bitacora.registrar(
      estado.usuario.username,
      "disconnect",
      "cliente finalizado",
      "ok"
    )

    {:stop, :normal, estado}
  end

  def handle_info(_mensaje, estado), do: {:noreply, estado}
end
