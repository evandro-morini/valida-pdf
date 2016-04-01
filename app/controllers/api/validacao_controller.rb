module Api
	class ValidacaoController < Api::BaseController
		require 'preflight'
		def index	

			preflight = Preflight::Profiles::PDFX1A.new
			@resultado = preflight.check("algum-arquivo.pdf")

		end
	end
end
