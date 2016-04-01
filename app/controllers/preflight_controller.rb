# coding: utf-8

require 'preflight'
require 'preflight/issue'
include Preflight::Measurements

class PreflightController < ApplicationController

  before_filter :add_cors_headers

  def add_cors_headers
    headers['Access-Control-Allow-Origin'] = '*'
=begin
    headers['Access-Control-Expose-Headers'] = 'ETag'
    headers['Access-Control-Allow-Methods'] = 'GET, POST, PATCH, PUT, DELETE, OPTIONS, HEAD'
    headers['Access-Control-Allow-Headers'] = '*,x-requested-with,Content-Type,If-Modified-Since,If-None-Match'
    headers['Access-Control-Max-Age'] = '86400'
	headers['Access-Control-Allow-Credentials'] = 'true'
=end
  end

  def index

    #nome do arquivo temporário
    filename = params["filename"]

    #caminho para a pasta de arquivos relativa a empresa
    filesPath = params["files_path"]

    #caminho completo do arquivo
    fullFilePath  = filesPath + filename

    #Quantidade de cores do verso
    convert = params["convert"]

    #altura do produto definida no banco de dados
    largura = params["largura"].sub(/,/) { "." }.to_f
    #largura do produto definida no banco de dados
    altura = params["altura"].sub(/,/) { "." }.to_f

    #Verifica o tamanho do arquivo enviado
    sizeMM = getFileSize(:MediaBox, filesPath, filename, 'mm')

    #lado da arte
    lado = params["lado"]

    #Quantidade de cores do verso
    qtdCores = params["qtdCores"]

    #se o produto é texturizado
    @texturizado = params["texturizado"]

    #Aqui verifica-se a necessidade de rotacionar o PDF
    rotate = rotatePdf(largura, altura, sizeMM)

    #instancia a classe
    preflight = Preflight::Profiles::PDFX1A.new

    # seta altura e largura a ser verificada
    if rotate == true
      if ((convert == false) || ((largura - sizeMM[1]).abs > 0.2) || ((altura - sizeMM[0]).abs > 0.2))
        preflight.rule Preflight::Rules::FileSize, altura, largura, sizeMM
      end
    elsif rotate == false
      if ((convert == false) || ((largura - sizeMM[0]).abs > 0.2) || ((altura - sizeMM[1]).abs > 0.2))
        preflight.rule Preflight::Rules::FileSize, largura, altura, sizeMM
      end
    end

    #Verifica a quantidade de cores no verso do produto 4x1
    #if ((qtdCores == "4x1" && lado == "2") || (qtdCores == "1x0" && lado == "1") || (qtdCores == "1x1")) #&& @baixa == true
    #  preflight.rule Preflight::Rules::OneColorValidator
    #end

    #Valida a existência de cores indevidas na máscara
    #if (lado== "3" || lado == "4")  #&& @baixa == true
    #  preflight.rule Preflight::Rules::MaskValidator
    #end

    begin
      #executa a validação
      @erros = preflight.check("#{fullFilePath}")
    rescue
      File.open("erro.txt", "w") do |arquivo_temporario|
        arquivo_temporario.puts "Erro ao validar " + fullFilePath
      end
    end

    if @rotateError != ""
      @erros << @rotateError
    end

    #valida cores sobreposta e gradiente
    findObjectIssue(filesPath, filename)

    #valida utilização de elementos posteriores a versão 1.3 dentro do documento PDF
    checkXRefStream(filesPath, filename)

    #verifica a existência de fontes não convertidas no PDF
    getFontIssue(filesPath, filename)

    #valida a existência de imagens no verso dos produtos 4x1 e na máscara
    #if ((lado == "2" && qtdCores == "4x1") || lado == "3" || lado == "4") #&& @baixa == true
    #  findImg4x1(filesPath + filename, qtdCores, lado)
    #end

    #adicional de verniz
    if (lado == "3" || lado == "4")
      processFileColors(filesPath + filename, qtdCores, lado)
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
    newThumbnail(filesPath,filename, largura, altura, rotate, lado, sizeMM, qtdCores) unless @critical == true

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

  #valida necessidade de rotacionar o arquivo PDF encaminhado pelo cliente
  def rotatePdf(largura, altura, sizeMM)
    fileWidth = sizeMM[0]
    fileHeight = sizeMM[1]
    @rotateError = ""
    rotateIssue = {Erro: "Arquivo enviado na orientação errada"}

    #verifica qual a orientação correta do arquivo enviado
    if(fileWidth >= fileHeight)
      fileOrientation = 0
    else
      fileOrientation = 1
    end

    #verifica a orientação correta do produto adquirido
    if(largura >= altura)
      productOrientation = 0
    else
      productOrientation = 1
    end

    #faz a rotação conforme a orientação do arquivo e do produto
    if(fileOrientation == productOrientation)
      return false
    else
      @rotateError = Preflight::Issue.new(0, "pdfview", "O arquivo enviado está na orientação errada", sizeMM, rotateIssue)
      return true
    end

  end

  #gera a thumb do pdf informado
  def newThumbnail(filepath, filename, largura, altura, rotate, lado, fileSize, qtdCores)

    #Caminho para o arquivo padrão do PDF X1a
    pdfSpecs = Rails.root + 'app/pdfspecs/PDFX_def.ps'  

    #nome da imagem (thumb) que será criada
    nome_tmp = filename.split('.')
    nome_img = "#{filepath}/thumb_" + nome_tmp.first + ".jpg"
    tiff_img = filepath + nome_tmp.first + ".tif"
    nova_img = nome_img.sub(/.jpg/) { "_crop.jpg" }

    # nome do arquivo pdf , que será a origem para gerar a thumb
    pdf = filepath + filename

    #Tamanho da Thumb em Pixels (px = (mm * dpi) / 25.4)
    width_pixel = (largura * 300) / 25.4 #Largura definitiva da Thumb em pixel (devido aos 300dpi)
    height_pixel = (altura * 300) / 25.4 #Altura definitiva da Thumb em pixel (devido aos 300dpi)
    pdf_width = (fileSize[0] * 300) / 25.4 #Largura em Pixel do Pdf REAL
    pdf_height = (fileSize[1] * 300) / 25.4 #Altura em Pixel do Pdf REAL

    begin
      
      if ((lado == "2" && qtdCores == "4x1") || qtdCores == "1x0" || qtdCores == "1x1" || lado == "3" || lado == "4")  
        temp_pdf = filepath + filename.sub(/.pdf/) { "_temp.pdf" }  
        system('gs -dPDFX -dBATCH -dNOPAUSE -dNOOUTERSAVE -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress -dProcessColorModel=/DeviceGray -sColorConversionStrategy=Gray -r300 -sOutputFile=' + "#{temp_pdf} " + "#{pdfSpecs} " + "#{pdf}")
        system('rm ' + "#{pdf}")
        system('mv ' + "#{temp_pdf}" + ' ' + "#{pdf}")
        
        #correção do contraste de preto
        system('convert -density 300 -quality 100 ' + "#{pdf}" + ' -contrast -contrast ' + "#{temp_pdf}")
        system('rm ' + "#{pdf}")
        system('mv ' + "#{temp_pdf}" + ' ' + "#{pdf}")
        system('gs -dPDFX -dBATCH -dNOPAUSE -dNOOUTERSAVE -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress -dProcessColorModel=/DeviceGray -sColorConversionStrategy=Gray -r300 -sOutputFile=' + "#{temp_pdf} " + "#{pdfSpecs} " + "#{pdf}")
        system('rm ' + "#{pdf}")
        system('mv ' + "#{temp_pdf}" + ' ' + "#{pdf}")

      end
      
      if @overprint == 0
        system('gs -sDEVICE=jpeg -dGraphicsAlphaBits=4 -dTextAlphaBits=4 -dNOPAUSE -dBATCH -q -dSAFER -r300 -sOutputFile=' + "#{nome_img} #{pdf}")
      elsif @overprint == 1
        system('gs -sDEVICE=tiff32nc -q -dGraphicsAlphaBits=4 -dTextAlphaBits=4 -dNOPAUSE -dBATCH -dSAFER -r300 -dSimulateOverprint=true -sOutputFile=' + "#{tiff_img} #{pdf} ")
        system('convert ' + "#{tiff_img} #{nome_img}") #-density 300 -quality 80
        system('rm ' + "#{tiff_img}")
      end

      if rotate == false
        #Geração da thumb com corte (arquivo maior que o item)
        if (fileSize[0] >= largura && fileSize[1] >= altura)
          system('convert '+ "#{nome_img}" + ' -gravity Center -crop '+ "#{width_pixel}" + 'x'+ "#{height_pixel}" + '+0+0 ' + "#{nova_img}")
          system('rm ' + "#{nome_img}")
          system('mv ' + "#{nova_img}" + ' ' + "#{nome_img}")
        else
          bordaWidth = (width_pixel - pdf_width) / 2
          bordaHeight = (height_pixel - pdf_height) / 2
          system('convert ' + "#{nome_img}" + ' -bordercolor White -border ' +  "#{bordaWidth}" + 'x'+ "#{bordaHeight} " + "#{nova_img}")
          system('rm ' + "#{nome_img}")
          system('mv ' + "#{nova_img}" + ' ' + "#{nome_img}")
        end

      elsif rotate == true
        #verifica se a thumb é menor e executa a correção
        if (fileSize[1] < largura || fileSize[0] < altura)
          bordaWidth = (height_pixel - pdf_width) / 2
          bordaHeight = (width_pixel - pdf_height) / 2
          system('convert ' + "#{nome_img}" + ' -bordercolor White -border ' +  "#{bordaWidth}" + 'x'+ "#{bordaHeight} " + "#{nova_img}")
          system('rm ' + "#{nome_img}")
          system('mv ' + "#{nova_img}" + ' ' + "#{nome_img}")
        end
        #Gera thumb rotacionada (se lado for FRENTE, FRENTE MÁSCARA ou FACA)
        if lado == "1" || lado =="3" || lado == "5"
          system('convert '+ "#{nome_img}" + ' -gravity Center -crop '+ "#{height_pixel}" + 'x'+ "#{width_pixel}" + '+0+0  -rotate -90 ' + "#{nova_img}")
          system('rm ' + "#{nome_img}")
          system('mv ' + "#{nova_img}" + ' ' + "#{nome_img}")

          #Gera thumb rotacionada (se lado for VERSO ou MÁSCARA VERSO)
        elsif lado == "2" || lado =="4"
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

  def findObjectIssue(filepath, filename)
    pdf = filepath + filename
    #cria um hash com todos os objetos do PDF
    reader = PDF::Reader.new(pdf)
    objects = reader.objects
    #percorre os objetos em busca do objeto overprint :op (preenchimento) e :OP (contorno)
    for i in 0..objects.size
      begin
        if (objects[i][:OPM] == 1) && (objects[i][:op] == true || objects[i][:OP] == true)
          @erros << Preflight::Issue.new(0, "colorview", "Cor sobreposta encontrada - Se você desejar que seja feita a sobreposição de cores clique em [NomeBotaoConfirma]", objects, objects[i])
          @overprint = 1
          break
        else
          @overprint = 0
        end

        if (objects[i][:ShadingType] > 0)
        	@erros << Preflight::Issue.new(0, "colorview", "Cor com gradiente encontrada", objects, objects[i])
        	break
        end

      rescue
        []
      end
    end

  end

  ######################VALIDAÇÃO DE CROSS REFERENCE STREAM NAS VERSÕES 1.3 DO PDF##################################################
  # Essa validação tem por objetivo barrar os arquivos de versão 1.3 que possuem Cross Reference Stream (estruturas presentes
  # apenas nas versões 1.5, causando erros no MPDF -> Biblioteca utilizada no Sistema da Matriz)

  def checkXRefStream(filepath, filename)
    pdf = filepath + filename
    reader = PDF::Reader.new(pdf)
    objects = reader.objects
    pdf_version = reader.pdf_version

    for i in 0..objects.size

      begin
        stream = objects[i].as_json
        xref = stream["hash"]["Type"]

        if xref == "XRef" && pdf_version <= 1.4
          versionIssue = {Erro: "PDF Versão #{pdf_version} com elementos de Cross Reference Stream"}
          @erros << Preflight::Issue.new(1, "pdfview", "Favor verificar a versão do seu arquivo PDF", objects, versionIssue)
          break
        elsif xref == "Pattern" && stream["hash"]["Resources"]["ProcSet"].include?("ImageC")
          versionIssue = {Erro: "PDF contém imagem como preenchimento padrão"}
          @erros << Preflight::Issue.new(0, "pdfview", "PDF contém imagem como preenchimento padrão, favor converter em bitmap.", objects, versionIssue)
          break
        end

      rescue
        []
      end

    end

  end
  ##################################################################################################################################
  #######################VALIDAÇÃO DE IMAGENS COLORIDAS NO VERSO DO PRODUTO 4x1 ####################################################
  #Essa validação ocorre somente para o verso dos produtos 4x1, para identificar a utilização de imagens coloridas não inseridas na
  #stream do arquivo PDF

  def findImg4x1(fullPathFilename, qtdCores, lado)
    pdf = fullPathFilename
    reader = PDF::Reader.new(pdf)
    objects = reader.objects
    colorIssue = {Erro: "Imagem encontrada no verso do produto 4x1"}
    if(lado == "3" || lado == "4")
      tipoArquivo = "a MÁSCARA"
    else
      tipoArquivo = "o VERSO"
    end

    for i in 0..objects.size

      begin
        stream = objects[i].as_json

        begin
          img = stream['Resources']['ProcSet']
          if img.include? ("ImageC")
            @erros << Preflight::Issue.new(0, "colorview", "Identificamos que #{tipoArquivo} contém imagens coloridas. <br/>Ressaltamos que somente tons de cinza ou o canal K da paleta CMYK serão impressos.", objects, colorIssue)
            break
          end
        rescue
          img = stream['ProcSet']
          if img.include? ("ImageC")
            @erros << Preflight::Issue.new(0, "colorview", "Identificamos que #{tipoArquivo} contém imagens coloridas. <br/>Ressaltamos que somente tons de cinza ou o canal K da paleta CMYK serão impressos.", objects, colorIssue)
            break
          end
        end

      rescue
        []
      end

    end

  end
  ##################################################################################################################################

  def processFileColors(fullPathFilename, qtdCores, lado)
    pdf = fullPathFilename
    reader = PDF::Reader.new(pdf)
    maskIssue = {Erro: "Verniz presente em mais de 30% do arquivo."}
    cmykIssue = {Erro: "Este arquivo não pode conter imagens coloridas"}
    rgbIssue = {Erro: "Arquivo possui imagem com cores RGB"}

    begin
      file_specs = `/usr/bin/identify -verbose "#{pdf}"`

      #if file_specs.include?("Colorspace: sRGB")
      #	@erros << Preflight::Issue.new(0, "colorview", "Arquivo possui imagem com cores RGB.", reader, rgbIssue)

      if file_specs.include?("Colorspace: Gray")
        gray_info = file_specs.split("Gray\:").last.split("standard").first.split(" ").last
        gray_percent = gray_info.sub(/\(/){ }.sub(/\)/){ }.to_f

        if((gray_percent > 0.35) && (lado == "3" || lado == "4"))
          @erros << Preflight::Issue.new(3, "pdfview", "Verniz presente em mais de 30% do arquivo.", reader, maskIssue)
        end

      elsif file_specs.include?("Colorspace: CMYK")
        cyan_info = file_specs.split("Cyan\:").last.split("standard").first.split(" ").last
        cyan_percent = cyan_info.sub(/\(/){ }.sub(/\)/){ }.to_f

        magenta_info = file_specs.split("Magenta\:").last.split("standard").first.split(" ").last
        magenta_percent = magenta_info.sub(/\(/){ }.sub(/\)/){ }.to_f

        yellow_info = file_specs.split("Yellow\:").last.split("standard").first.split(" ").last
        yellow_percent = yellow_info.sub(/\(/){ }.sub(/\)/){ }.to_f

        black_info = file_specs.split("Black\:").last.split("standard").first.split(" ").last
        black_percent = black_info.sub(/\(/){ }.sub(/\)/){ }.to_f

        total_info = file_specs.split("Total ink density\:").last.split("%").first.sub(/ /) { "" }.to_f

        #if(((black_percent < yellow_percent || yellow_percent > 0.50) ||
        #	(black_percent < magenta_percent || magenta_percent > 0.50) ||
        #	(black_percent < cyan_percent || cyan_percent > 0.50)) && total_info > 260.0)
        #	@erros << Preflight::Issue.new(0, "colorview", "Este arquivo não pode conter imagens coloridas.", reader, cmykIssue)

        if((black_percent > 0.35) && (lado == "3" || lado == "4"))
          @erros << Preflight::Issue.new(3, "pdfview", "Verniz presente em mais de 30% do arquivo.", reader, maskIssue)
        end

      end

    rescue
      File.open("erro.txt", "a") do |arquivo_temporario|
        arquivo_temporario << "Erro ao verificar cores e imagens do arquivo \n"
      end
    end

  end

  def getFontIssue(filepath, filename)
    pdf = filepath + filename
    reader = PDF::Reader.new(pdf)
    objects = reader.objects
    fontIssue = {Erro: "Arquivo com fonte não convertida"}

    for i in 0..objects.size

      begin
        stream = objects[i].as_json
        type = stream['Type']
        if type.include? ("Font")
          @erros << Preflight::Issue.new(0, "pdfview", "O Arquivo PDF possui fontes não convertidas em curvas ou não incorporadas. Isso pode causar alterações no resultado final do seu impresso.", objects, fontIssue)
          #File.open("fonts_log.txt", "a") do |arquivo_temporario|
          #	arquivo_temporario << "#{pdf} \n"
          #end
          break
        end
      rescue
        []
      end

    end

  end

end

