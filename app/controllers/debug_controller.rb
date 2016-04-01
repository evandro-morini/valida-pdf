require 'preflight'
require 'preflight/issue'
include Preflight::Measurements

class DebugController < ApplicationController

	def index


		dados = Hash.new
		dados["filename"] 		= "6dedo.pdf"
		dados["files_path"] 	= "/baixa/atualcard/arquivos/tmp/"
		dados["largura"]	= "91.0"
		dados["altura"] 	= "51.2"
		dados["lado"] 		= "frente"

		#logger.debug "New post: #{dados.inspect}"

		#nome do arquivo temporário
		filename = dados["filename"].to_s

		#caminho para a pasta de arquivos relativa a empresa
		filesPath = dados["files_path"].to_s

		#caminho completo do arquivo
		fullFilePath  = filesPath+filename

		#altura do produto definida no banco de dados
		largura = dados["largura"].sub(/,/) { "." }.to_f
		#largura do produto definida no banco de dados
		altura = dados["altura"].sub(/,/) { "." }.to_f

		#Verifica o tamanho do arquivo enviado
		sizeMM = getFileSize(:MediaBox, filesPath, filename, 'mm')

		#lado da arte
		lado = dados["lado"]

		#Aqui verifica-se a necessidade de rotacionar o PDF
		if (largura == sizeMM[1] && altura == sizeMM[0])
			rotate = true
		else
			rotate = false
		end

		#instancia a classe
		preflight = Preflight::Profiles::PDFX1A.new

		# seta altura e largura a ser verificada
		if rotate == false
			preflight.rule Preflight::Rules::FileSize, largura, altura, sizeMM
		end

		#Valida a existência de cores indevidas na máscara
		if lado.include? "3"
			preflight.rule Preflight::Rules::MaskValidator

		#Caso não seja máscara, valida preto carregado
		else
			preflight.rule Preflight::Rules::ColorValidator
		end
		
		begin
			#executa a validação
			@erros = preflight.check("#{fullFilePath}")
		rescue
			File.open("erro.txt", "w") do |arquivo_temporario|
				arquivo_temporario.puts "Erro ao validar " + fullFilePath
			end
		end

		#Separa erros críticos de Warnings e Verifica necessidade de cortar o PDF
		if @erros.empty?
			@critical = false
		else
			@erros.each do |erro|
				value = erro.critical
				if value == 1
					@critical = true
					break
				else
					@critical = false
				end
			end	
		end

		#caso não contenha erros críticos, gera a thumb
		newThumbnail(filesPath,filename, largura, altura, rotate, lado, sizeMM) unless @critical == true

		#retorna a resposta no formatom requisitado , padrão é JSON
		respond_to do |format|
	      format.html # show.html.erb
	      format.js  { render :json => @erros, :callback => dados[:callback] }
	      format.json  { render :json => @erros }
	      format.xml  { render :xml => @erros }
	    end

	end

	#Função que recebe o arquivo e o box desejado e devolve o tamanho do PDF na medida solicitada (pt ou mm)
	def getFileSize(box, filepath, filename, units)
		pdf = filepath + filename

		
		reader = PDF::Reader.new(pdf)
		page = reader.page(1)
  		attributes = page.attributes
  		begin
  			box_width = attributes[box][2] - attributes[box][0]
        	box_height = attributes[box][3] - attributes[box][1]
			size = [box_width, box_height]
			if units == 'mm'
				size[0] = pt2mm(size[0])
				size[1] = pt2mm(size[1])
			end
			return size
		rescue
			return 0
		end		
  	end
	
	#gera a thumb do pdf informado
	def newThumbnail(filepath, filename, largura, altura, rotate, lado, fileSize)	

		#nome da imagem (thumb) que será criada
		nome_img = "#{filepath}/thumb_" + filename.sub(/.pdf/) { ".jpg" }		
		nova_img = nome_img.sub(/.jpg/) { "_crop.jpg" }

		# nome do arquivo pdf , que será a origem para gerar a thumb
		pdf = filepath + filename

		#Tamanho da Thumb em Pixels (px = (mm * dpi) / 25.4)
		width_pixel = (largura * 300) / 25.4 #Largura definitiva da Thumb em pixel (devido aos 300dpi)
		height_pixel = (altura * 300) / 25.4 #Altura definitiva da Thumb em pixel (devido aos 300dpi)

		begin
			#geração da thumb quando o arquivo atende todos os requisitos (resolução -r600 dpi ou -r300 dpi)
			system('gs -sDEVICE=jpeg -dGraphicsAlphaBits=4 -dTextAlphaBits=4 -dNOPAUSE -dBATCH -q -dSAFER -r300 -sOutputFile=' + "#{nome_img} #{pdf}")
			
			if rotate == false		
				#Geração da thumb com corte (arquivo maior que o item)
				if (fileSize[0] >= largura && fileSize[1] >= altura)
					system('convert '+ "#{nome_img}" + ' -gravity Center -crop '+ "#{width_pixel}" + 'x'+ "#{height_pixel}" + '+0+0 ' + "#{nova_img}")
					system('rm ' + "#{nome_img}")
					system('mv ' + "#{nova_img}" + ' ' + "#{nome_img}")
				end

			elsif rotate == true
				#Gera thumb da FRENTE rotacionada
				if lado.include? "frente"
					system('convert '+ "#{nome_img}" + ' -gravity Center -crop '+ "#{height_pixel}" + 'x'+ "#{width_pixel}" + '+0+0  -rotate -90 ' + "#{nova_img}")
					system('rm ' + "#{nome_img}")
					system('mv ' + "#{nova_img}" + ' ' + "#{nome_img}")

				#Gera thumb do VERSO rotacionado
				elsif lado.include? "verso"
					system('convert '+ "#{nome_img}" + ' -gravity Center -crop '+ "#{height_pixel}" + 'x'+ "#{width_pixel}" + '+0+0  -rotate 90 ' + "#{nova_img}")
					system('rm ' + "#{nome_img}")
					system('mv ' + "#{nova_img}" + ' ' + "#{nome_img}")
				end
			end
			

		rescue
			File.open("erro_gera_thumb.txt", "w") do |arquivo_temporario|
				arquivo_temporario.puts "Erro ao tentar escrever a thumb"
			end
			false
		end

	end

end

