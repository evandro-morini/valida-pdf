# coding: utf-8

require 'yaml'
require 'matrix'

module Preflight
  module Rules

    # Most CMYK printers will have a stated upper tolerance for ink density. If
    # the total percentage of the 4 components (C, M, Y and K) is over that
    # tolerance then the result can be unpredictable and often ugly.
    #
    # Use this rule to detect CMYK ink densities over a certain threshold.
    #
    # Arguments: the highest density that is Ok
    #
    # Usage:
    #
    #   class MyPreflight
    #     include Preflight::Profile
    #
    #     rule Preflight::Rules::MaxInkDensity, 300
    #   end
    #
    # TODO:
    #
    # * check CMYK colours used as alternates in a separation color
    # * check CMYK raster images
    #
    class MaxInkDensity

      attr_reader :issues

      def initialize(max_ink)
        @max_ink = max_ink.to_i
      end

      # we're about to start a new page, reset state
      #
      def page=(page)
        @issues = []
        @page    = page
        @objects = page.objects
      end

      def set_cmyk_color_for_nonstroking(c, m, y, k)
        check_ink(c, m, y, k)
      end

      def set_cmyk_color_for_stroking(c, m, y, k)
        check_ink(c, m, y, k)
      end

      private

      def check_ink(c, m, y, k)
        ink = (c + m + y + k) * 100.0
        cyan = c * 100.0
        magenta = m * 100.0
        yellow = y * 100.0
        black = k * 100.0
        average = ink / 4.0

        if 
          #Valida Preto carregado
          (ink > @max_ink && @issues.empty? && average > 70.0 && black > 85.0) || 
          #Valida Azul carregado
          (ink > @max_ink && @issues.empty? && cyan == 100.0 && magenta == 100.0)
          
          @issues << Issue.new("PDF possui cores carregadas", self, :page    => @page.number,
                                                             :cyan    => c,
                                                             :magenta => m,
                                                             :yellow  => y,
                                                             :k       => k)
        end
      end
    end

  end
end
