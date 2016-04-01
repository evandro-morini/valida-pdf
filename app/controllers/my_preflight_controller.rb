class PreflightController < ApplicationController
	
	require 'preflight'
	
	def index
		
		preflight = Preflight::Profiles::PDFX1A.new
		preflight.rule Preflight::Rules::PageBoxWidth, :MediaBox, 91.0, :mm
		preflight.rule Preflight::Rules::PageBoxHeight, :MediaBox, 51.2, :mm

		filename = params["filename"]

		filename ||= "64111a9461b4d7320fff89bd233de057.pdf"

		@erros = preflight.check(%{\\\\ivone\\atualtec.dev\\atual.dev\\srv\\baixa\\empresa\\arquivos\\tmp\\#{filename}});		

		#@erros = contentFix(%{\\\\ivone\\atualtec.dev\\atual.dev\\srv\\baixa\\empresa\\arquivos\\tmp\\#{filename}})
		
		
		respond_to do |format|
	      format.html # show.html.erb
	      format.js  { render :json => @erros, :callback => params[:callback] }
	      format.json  { render :json => @erros }
	      format.xml  { render :xml => @erros }
	    end

	end

	def contentFix(filename)
		reader = PDF::Reader.new(filename)
		page = reader.page(1)
  		@content = page.raw_content
		
  		begin
  			@content = @content.split " "
  		rescue
  			@error = "Não foi possível verificar o stream do arquivo"
  			puts @error
  		end

	end

	

end

