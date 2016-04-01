class PreflightController < ApplicationController

	require 'preflight'
	require 'preflight/issue'
	include Preflight::Measurements

	
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

		#lado da arte
		lado = params["lado"]

		#AQUI VERIFICA-SE A NECESSIDADE DE ROTACIONAR O PDF
		rotate = isPdfRotate(filesPath, filename, largura, altura)

		#Definindo o parâmetro da validação de width/height
		metrics = "#{largura}x#{altura}"

		#instancia a classe
		preflight = Preflight::Profiles::PDFX1A.new

		# seta altura e largura a ser verificada
		if rotate == false
			preflight.rule Preflight::Rules::PageBoxSize, :MediaBox, { :width => largura, :height => altura, :units => :mm }, metrics
		end

		# nome padrão caso nenhum seja enviado (acesso direto)
		filename ||= "0a3f4ce34426b812b8463346bd288716.pdf"
		
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
				sizeException = erro.rule.to_s
				if value == 1
					@critical = true
					break
				else
					@critical = false
					if sizeException == 'Preflight::Rules::PageBoxSize'
						isSmallerPdf(filesPath, filename, largura, altura)
					end
				end
			end	
		end

		#caso não contenha erros críticos, gera a thumb
		newThumbnail(filesPath,filename, largura, altura, rotate, lado) unless @critical == true

		#retorna a resposta no formatom requisitado , padrão é JSON
		respond_to do |format|
	      format.html # show.html.erb
	      format.js  { render :json => @erros, :callback => params[:callback] }
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
	def newThumbnail(filepath, filename, largura, altura, rotate, lado)

		#Verifica o tamanho real do arquivo
		fileSize = getFileSize(:MediaBox, filepath, filename, 'mm')			

		#nome da imagem (thumb) que será criada
		nome_img = "#{filepath}/thumb_" + filename.sub(/.pdf/) { ".jpg" }		
		nova_img = nome_img.sub(/.jpg/) { "_crop.jpg" }

		# nome do arquivo pdf , que será a origem para gerar a thumb
		pdf = filepath + filename

		#Tamanho da Thumb em Pixels
		#width_pixel = largura * 23.625 #Largura definitiva da Thumb em pixel (devido aos 600dpi)
		#height_pixel = altura * 23.625 #Altura definitiva da Thumb em pixel (devido aos 600dpi)
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
				if lado == 'frente'
					system('convert '+ "#{nome_img}" + ' -gravity Center -crop '+ "#{height_pixel}" + 'x'+ "#{width_pixel}" + '+0+0  -rotate -90 ' + "#{nova_img}")
					system('rm ' + "#{nome_img}")
					system('mv ' + "#{nova_img}" + ' ' + "#{nome_img}")

				#Gera thumb do VERSO rotacionado
				elsif lado == 'verso'
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

	#verifica se o arquivo enviado é menor do que o padrão
	def isSmallerPdf(filepath, filename, largura, altura)

		#converte medidas do produto em pt
		largura = mm2pt(largura)
		altura = mm2pt(altura)

		#Verifica o tamanho real do arquivo
		size = getFileSize(:MediaBox, filepath, filename, 'pt')
		file_width = size[0]
		file_height = size[1]

		#nome do PDF que será criado
		pdf_crop = filepath + filename.sub(/.pdf/) { "_crop.pdf" }

		# nome do arquivo pdf antigo
		pdf = filepath + filename

		#Confronta o tamanho do arquivo X tamanho do produto, caso o arquivo seja menor, gera uma nova exceção
		if (size[0] < largura || size[1] < altura)
			small = Preflight::Issue.new(2, "sizeview", "Arquivo menor que o tamanho esperado",
              		self,
              		:page => 1,
              		:box => 'MediaBox',
              		:box_width => file_width,
              		:box_height => file_height)
			@erros << small
		end

	end

	#verifica se o arquivo enviado está rotacionado
	def isPdfRotate(filepath, filename, largura, altura)
		
		#Verifica o tamanho real do arquivo
		sizes = getFileSize(:MediaBox, filepath, filename, 'mm')

		#nome do PDF que será criado
		pdf_rotate = filepath + filename.sub(/.pdf/) { "_rotate.pdf" }

		# nome do arquivo pdf antigo
		pdf = filepath + filename

		#Retorna verdadeiro se o arquivo estiver rotacionado e falso caso esteja na posição certa
		if 	(largura == sizes[1] && altura == sizes[0])			
			return true
		else
			return false
		end
	end


end

