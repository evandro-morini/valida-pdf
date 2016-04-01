class WelcomeController < ApplicationController
  def index
  	@parametros = params["filename"]
  	@parametros ||= "nada veio"
  end
end
