require 'uri'
require 'csv'

class TopContainersLabelsController < TopContainersController

  set_access_control  "view_repository" => [:show, :typeahead, :bulk_operations_browse, :print_labels]
 
  def print_labels
    post_uri = "/repositories/#{session[:repo_id]}/top_containers_labels/print_labels"
    response = JSONModel::HTTP.post_form(URI(post_uri), {"record_uris[]" => Array(params[:record_uris])})

    results = ASUtils.json_parse(response.body)

    if response.code =~ /^4/
      return render_aspace_partial :partial => 'top_containers/bulk_operations/error_messages', :locals => {:exceptions => results, :jsonmodel => "top_container"}, :status => 500
    end
    if params['csv'] == 'true'
      send_data labels_csv(results, params), filename: "labels_#{Time.now.to_i}.csv"      
    else
      render_aspace_partial :partial => "labels/bulk_action_labels", :locals => {:labels => results}
    end
  end

  def bulk_operation_search
    super
  end
end
# path = 't.csv'
# CSV.open(path, 'w', headers: ['Name', 'Value'], write_headers: true) do |csv|
#   csv << ['Foo', 0]
#   csv << ['Bar', 1]
#   csv << ['Baz', 2]
# end
# add in the indicator range search
def labels_csv(results, params)
  #Get the possible fields 
  fields = AppConfig[:container_management_labels].map{|h| h.keys}.flatten
  # narrow down the fields list to the selected fields
  valid_fields = params.keys.select{|key| fields.index(key) && params[key]}
  headers = []
  valid_fields.each do |k|
    headers << I18n.t("top_container_labels._frontend.fields.#{k}", :default => k) 
  end

  CSV.generate(headers: true) do |csv|
    csv << headers
    results.each do |result|
      row = []
      valid_fields.each do |k|
        value = result[k] || ''
        value = value.titlecase if k == 'type'
        row << value
      end
      csv << row
    end
   csv
  end
end

class TopContainersController

  private
  
  alias old_perform_search perform_search

  def perform_search
    unless params[:indicator].blank?
      unless params[:q].blank?
        params[:q] = "#{params[:q]} AND "
      end
      
      #convert the range into a set of indicators since indicators are defined as strings and we need exact matches
      if params[:indicator].downcase.include? "to"
        range = params[:indicator].split
          .find_all{|e| e[/\d+/]}
          .each{|e| e.gsub!(/\[|\]/,'').to_i}
          
        indicators = (range[0]..range[range.length-1]).step(1).to_a
      # otherwise just split the list up
      else
        indicators = params[:indicator].split
      end
      
      # then concatenate with the correct prefix and OR the search
      indicator_string = indicators.each { |e| e.prepend('indicator_u_stext:') }.join(" OR ")
      
      params[:q] << indicator_string
    end

    old_perform_search
  end
end
