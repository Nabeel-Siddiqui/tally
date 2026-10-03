defmodule TallyWeb.AccountLive.FormComponent do
  @moduledoc """
  The "new account" form, shown in a modal from `AccountLive.Index`.
  """

  use TallyWeb, :live_component

  alias Tally.Finance

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>A bank or credit card account to track transactions for.</:subtitle>
      </.header>

      <.simple_form for={@form} id="account-form" phx-target={@myself} phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" placeholder="Everyday Checking" />
        <.input
          field={@form[:type]}
          type="select"
          label="Type"
          prompt="Choose a type"
          options={[{"Checking", :checking}, {"Credit card", :credit_card}]}
        />
        <:actions>
          <.button phx-disable-with="Saving...">Save account</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(Finance.change_account(assigns.account)))}
  end

  @impl true
  def handle_event("save", %{"account" => account_params}, socket) do
    case Finance.create_account(socket.assigns.current_user, account_params) do
      {:ok, account} ->
        notify_parent({:saved, account})

        {:noreply,
         socket
         |> put_flash(:info, "Account created")
         |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
