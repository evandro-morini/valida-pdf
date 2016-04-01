json.array!(@erros) do |erro|
  json.extract! erro, :description, :attributes, :rule  
end