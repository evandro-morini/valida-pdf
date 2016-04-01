require 'preflight'
require 'preflight/issue'

include Preflight::Measurements

class Convert2pdfController < ApplicationController
  def index

    # Caminho onde os arquivos são armazenados
    temp_path = params["files_path"];

    # Caminho onde os arquivos de predefinição (PS e ICC) são armazenados
    defn_path = '/srv/www/website/atualtec.dev/atual.dev/erp/scripts/valida-pdf/app/pdfspecs/';

    # Nome do arquivo temporário
    @filename = params["filename"]

    #lado da arte
    lado = params["lado"]

    #Quantidade de cores do verso
    qtdCores = params["qtdCores"]

    # Nome do PDF
    pdf_name  = @filename.split(".").first + ".pdf"

    # Extensão do arquivo temporario
    ext_file  = @filename.split(".").last

    begin
      if ext_file == 'cdr' # cdr
        #converte o cdr em pdf
        #system('soffice --headless --convert-to pdf:draw_pdf_Export ' + "#{temp_path}#{@filename}" + ' --outdir ' + "#{temp_path}")
        #s = `soffice --headless --invisible --convert-to pdf:draw_pdf_Export /srv/www/website/atualtec.dev/atual.dev/srv/baixa/empresa/arquivos/tmp/9c4ebee18ba4a646476c421bab9f6f29.cdr --outdir /srv/www/website/atualtec.dev/atual.dev/srv/baixa/empresa/arquivos/tmp/`
        s = %x(soffice --version)

        # Create a new file and write to it  
		File.open(defn_path + 'debug.txt', 'w') do |f2|  
		  # use "\n" for two lines of text  
		  #f2.puts('soffice --headless --convert-to pdf:draw_pdf_Export ' + temp_path + @filename + ' --outdir ' + temp_path)
		  f2.puts('----------------')
		  f2.puts s
		end  

        #renomeia o arquivo, criando um temporario
        system('mv ' + "#{temp_path}#{pdf_name}" + ' temp_' + "#{pdf_name}")

        #Verifica a quantidade de cores no verso do produto 4x1
        if ((qtdCores == "4x1" && lado == "2") || (qtdCores == "1x0" && lado == "1") || (qtdCores == "1x1") || (lado == "3" || lado == "4"))
          #converte para PDF/x1-a:2001 e Grayscale
          #system('gs -dPDFX -dBATCH -dNOPAUSE -dNOOUTERSAVE -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress -dProcessColorModel=/DeviceGray -sColorConversionStrategy=Gray -sColorConversionStrategyForImages=Gray -sOutputFile="' + "#{temp_path}#{pdf_name}" + '" ' + "#{defn_path}" + 'PDFX_def.ps ' + "#{temp_path}temp_#{pdf_name}")
        else
          #converte para PDF/x1-a:2001 e CMYK
          #system('gs -dPDFX -dBATCH -dNOPAUSE -dNOOUTERSAVE -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress -dProcessColorModel=/DeviceCMYK -sColorConversionStrategy=CMYK -sColorConversionStrategyForImages=CMYK -sOutputFile="' + "#{temp_path}#{pdf_name}" + '" ' + "#{defn_path}" + 'PDFX_def.ps ' + "#{temp_path}temp_#{pdf_name}")
        end

      else # jpg ou jpeg
        #converte o jpg em pdf
        system('convert ' + "#{temp_path}#{@filename} #{temp_path}temp_#{pdf_name}")

        #Verifica a quantidade de cores no verso do produto 4x1
        if ((qtdCores == "4x1" && lado == "2") || (qtdCores == "1x0" && lado == "1") || (qtdCores == "1x1") || (lado == "3" || lado == "4"))
          #converte para PDF/x1-a:2001 e Grayscale
          system('gs -dPDFX -dBATCH -dNOPAUSE -dNOOUTERSAVE -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress -dProcessColorModel=/DeviceGray -sColorConversionStrategy=Gray -sColorConversionStrategyForImages=Gray -sOutputFile="' + "#{temp_path}#{pdf_name}" + '" ' + "#{defn_path}" + 'PDFX_def.ps ' + "#{temp_path}temp_#{pdf_name}")
        else
          #converte para PDF/x1-a:2001 e CMYK
          system('gs -dPDFX -dBATCH -dNOPAUSE -dNOOUTERSAVE -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress -dProcessColorModel=/DeviceCMYK -sColorConversionStrategy=CMYK -sColorConversionStrategyForImages=CMYK -sOutputFile="' + "#{temp_path}#{pdf_name}" + '" ' + "#{defn_path}" + 'PDFX_def.ps ' + "#{temp_path}temp_#{pdf_name}")
        end

      end
    end

    respond_to do |format|
      format.html # show.html.erb
      format.json  { render :json => pdf_name }
    end

  end

end