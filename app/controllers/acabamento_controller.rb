# coding: utf-8

require 'preflight'
require 'preflight/issue'
include Preflight::Measurements

class AcabamentoController < ApplicationController

	def index
		#nome do arquivo temporário
		filename = params["filename"]

		#caminho para a pasta de arquivos relativa a empresa
		filesPath = params["files_path"]

		#caminho completo do arquivo
		fullFilePath  = filesPath+filename

		#altura do produto definida no banco de dados
		largura = params["largura"].sub(/,/) { "." }.to_f
		#largura do produto definida no banco de dados
		altura = params["altura"].sub(/,/) { "." }.to_f

		#Localização do furo no PDF
		furo = params["furo"]

		#valida a criação do pdf para a loja
		@retorno = false

		#Verifica o tamanho do arquivo enviado
		sizeMM = getFileSize(:MediaBox, filesPath, filename, 'mm')

		if furo.include?("_")
			furoParams = furo.split("_");

			#Recebendo e transformando os tamanhos a marcação fixa de 1mm em pixel
			punctureSize = 6
			
			#largura
			xPoint = furoParams[0].to_f
			xPoint = xPoint * sizeMM[0]
			xPoint = (xPoint * 300) / 25.4

			#altura
			yPoint = furoParams[1].to_f
			yPoint = yPoint * sizeMM[1]
			yPoint = (yPoint * 300) / 25.4

			xPuncture = xPoint + punctureSize
			yPuncture = yPoint + punctureSize

			#Definindo caminho e nomes dos arquivos
			temp_pdf = filesPath + filename.sub(/.pdf/) { "_furo.pdf" }

			#Caminho para o arquivo padrão do PDF X1a
			pdfSpecs = Rails.root + 'app/pdfspecs/PDFX_def.ps'

			#Marcação Thumb
			nome_tmp = filename.split('.')
			thumb_temp = "#{filesPath}/thumb_" + nome_tmp.first + "_furo.jpg"
    		nome_img = "#{filesPath}/thumb_" + nome_tmp.first + ".jpg"

			furoThumb = furoParams[2].to_f
			tamanhoFuro = (furoThumb * (BigDecimal.new("72") / BigDecimal.new("25.4"))) + 8.503937
			rotacionado = furoParams[3]

			thumbWidth = furoParams[0].to_f
			if rotacionado == "true"
				thumbWidth = furoParams[1].to_f		
			end
			xThumb = thumbWidth * largura
			xThumb = (xThumb * 300) / 25.4

			thumbHeight = furoParams[1].to_f
			if rotacionado == "true"
				thumbHeight = (furoParams[0].to_f - 1) * (-1)				
			end
			yThumb = thumbHeight * altura
			yThumb = (yThumb * 300) / 25.4

			xDiametro = xThumb + tamanhoFuro
			yDiametro = yThumb + tamanhoFuro

			begin
				#Criação do novo PDF com o furo
				system('convert -density 300 -quality 100 ' + "#{fullFilePath}" + " -units PixelsPerInch -fill blue -stroke white -draw \"circle " + "#{xPoint}, #{yPoint}, #{xPuncture}, #{yPuncture}\"" + " #{temp_pdf}")
				system('rm ' + "#{fullFilePath}")
				system('mv ' + "#{temp_pdf}" + ' ' + "#{fullFilePath}")
				system('gs -dPDFX -dBATCH -dNOPAUSE -dNOOUTERSAVE -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress -dProcessColorModel=/DeviceCMYK -sColorConversionStrategy=CMYK -sOutputFile=' + "#{temp_pdf} " + "#{pdfSpecs} " + "#{fullFilePath}")
				system('rm ' + "#{fullFilePath}")
				system('mv ' + "#{temp_pdf}" + ' ' + "#{fullFilePath}")
				#Marcacao da Thumb
				system('convert -density 300 ' + "#{nome_img}" + " -units PixelsPerInch -fill yellow -stroke black -draw \"circle " + "#{xThumb}, #{yThumb}, #{xDiametro}, #{yDiametro}\"" + " #{thumb_temp}")
				system('rm ' + "#{nome_img}")
				system('mv ' + "#{thumb_temp}" + ' ' + "#{nome_img}")
				@retorno = true
			rescue
				@retorno = false
			end

		end

		#retorna a resposta no formatom requisitado , padrão é JSON
		respond_to do |format|
	      format.html # show.html.erb
	      format.js  { render :json => @retorno, :callback => params[:callback] }
	      format.json  { render :json => @retorno }
	      format.xml  { render :xml => @retorno }
	    end

	end

	#Função que recebe o arquivo e o box desejado e devolve o tamanho do PDF na medida solicitada (pt ou mm)
	def getFileSize(box, filepath, filename, units)
		pdf = filepath + filename
		reader = PDF::Reader.new(pdf)
		metadata = reader.metadata
		page = reader.page(1)
  		attributes = page.attributes
  		begin
  			box_width = attributes[box][2] - attributes[box][0]
        	box_height = attributes[box][3] - attributes[box][1]
        	
        	begin
  				if metadata.include?("Adobe Photoshop")
  					box_width += 0.1
  					box_height += 0.1
  					size = [box_width, box_height]
  				else
  					size = [box_width, box_height]
  				end
  			rescue
  				size = [box_width, box_height]
  			end
        	
			if units == 'mm'
				size[0] = pt2mm(size[0])
				size[1] = pt2mm(size[1])
			end
			return size
		rescue
			return 0
		end		
  	end
	
end