module Api
  class ArticlesController < Api::BaseController

private

    def article_params
	   	params.require(:article).permit(:title, :text)
	end

    def query_params
        params.permit(:text, :title)
    end

end
end