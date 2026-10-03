defmodule TallyWeb.CategoryRuleLive.FormComponent do
  @moduledoc """
  The "new category rule" form, shown in a modal from
  `CategoryRuleLive.Index`.
  """

  use TallyWeb, :live_component

  alias Tally.Finance

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          Any future import where the merchant contains this text gets filed under this category.
        </:subtitle>
      </.header>

      <.simple_form for={@form} id="category-rule-form" phx-target={@myself} phx-submit="save">
        <.input
          field={@form[:match_text]}
          type="text"
          label="Merchant contains"
          placeholder="NETFLIX"
        />
        <.input field={@form[:category]} type="text" label="Category" placeholder="Subscriptions" />
        <:actions>
          <.button phx-disable-with="Saving...">Save rule</.button>
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
     |> assign(:form, to_form(Finance.change_category_rule(assigns.category_rule)))}
  end

  @impl true
  def handle_event("save", %{"category_rule" => rule_params}, socket) do
    case Finance.create_category_rule(socket.assigns.current_user, rule_params) do
      {:ok, rule} ->
        notify_parent({:saved, rule})

        {:noreply,
         socket
         |> put_flash(:info, "Category rule created")
         |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
