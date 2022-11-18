# Load Romanizer (to convert series numbers from Arabic [well-actually-Hindi] to Roman)
romanize_lib = ASUtils.find_local_directories('public/models/romanize_series_identifier.rb',
                                              'aspace_yale_pui').first

if File.exist?(romanize_lib)
  load romanize_lib
else
  raise "container_management_labels needs the aspace_yale_pui to be loaded first.  File could not be found: #{romanize_lib}"
end

require 'aspace_logger'
require 'pp'
class LabelData

  include JSONModel
  
  attr_accessor :labels, :sub_labels

  def initialize(uris)
    @uris = uris
    @labels = build_label_data
    @sub_labels = build_subcontainer_data
  end

  def romanize_series_id(series_identifier)
    if series_identifier =~ /\A(Series )?([0-9]+)\z/
      series_identifier_transformed = Romanizer.romanize(Integer($2))
    else
      series_identifier_transformed = series_identifier
    end

    return series_identifier_transformed
  end

  def build_label_data
    @tag = AppConfig.has_key?(:container_management_labels_series)? AppConfig[:container_management_labels_series] : ''
    @delim = AppConfig.has_key?(:container_management_labels_delim)? AppConfig[:container_management_labels_delim] : '; '
    ids = @uris.map {|uri| JSONModel(:top_container).id_for(uri)}
    
    # Eagerly load all of the Top Containers we'll be working with
    load_top_containers(ids)
    
    labels = []
        
    # create a label for each top container
    ids.each do |top_container_id|
      tc = fetch_top_container(top_container_id)
      agent = agent_for_top_container(tc)
      area, location, location_barcode = location_for_top_container(tc)
      resource_id, resource_title = resource_for_top_container(tc)
      institution, repository = institution_repo_for_top_container(tc)
      series_id, series_display = series_for_top_container(tc)

      labels << tc.merge({
                  "agent_name" => agent,
                  "area" => area,
                  "location" => location,
                  "location_barcode" => location_barcode,
                  "resource_id" => resource_id,
                  "resource_title" => resource_title,
                  "institution_name" => institution,
                  "repository_name" => repository,
                  "series_id" => series_id,
                  "series_display" => series_display,
                  })
    end
    
    return labels
  end
  
  def build_subcontainer_data
    
    ids = @uris.map {|uri| JSONModel(:top_container).id_for(uri)}
    
    # Eagerly load all of the Top Containers we'll be working with
    load_top_containers(ids)
    
    # Pre-store the links between our top containers and the archival objects they link to
    top_container_to_ao_links = calculate_top_container_linkages(ids)
    
    subcontainer_labels = []
    
    # create a label for each top container
    ids.each do |top_container_id|
      tc = fetch_top_container(top_container_id)
      agent = agent_for_top_container(tc)
      area, location, location_barcode = location_for_top_container(tc)
      resource_id, resource_title = resource_for_top_container(tc)
      institution, repository = institution_repo_for_top_container(tc)
      series_id, series_display = series_for_top_container(tc)
      
      # if there's an indicator2, then its a sub_container like a file so add it to the sub_container labels
      unless top_container_to_ao_links[top_container_id].nil?
        top_container_to_ao_links[top_container_id].each do |ao|
          
          # skip this ao if it is not in the list of levels to print
          if AppConfig[:container_management_labels_print_levels] && AppConfig[:container_management_labels_print_levels].count > 0
            next unless AppConfig[:container_management_labels_print_levels].include? (ao["level"])
          end
          
          # replace the tc indicator with a concatted string from the subcontainer
          sc_ind = []
          if tc['type']
            sc_ind.push(tc["type"].capitalize + " " + tc["indicator"])
          else
            sc_ind.push(tc["indicator"])
          end        
          # if there is no type2, replace it with the title
          # this will cover AOs without child indicators
          # otherwise, if there is a type2, then concat that with indicator2
          # same for type3 and indicator3
          # we should end up with an array that looks like: ["Box 1", "File 2", Item 3"] or ["{FILE_TITLE}"]
          
          if ao["type2"].nil?
            ao["type2"] = ao["title"]
          else
            unless ao["indicator2"].nil?
              sc_ind.push(ao["type2"].capitalize + " " + ao["indicator2"])
            end
            if !ao["type3"].nil? && !ao["indicator3"].nil?
              sc_ind.push(ao["type3"].capitalize + " " + ao["indicator3"])
            end
          end
          
          subcontainer_labels << tc.merge({
                      "sc_indicator" => sc_ind.compact.join(", "),
                      "agent_name" => agent,
                      "area" => area,
                      "location" => location,
                      "location_barcode" => location_barcode,
                      "resource_id" => resource_id,
                      "resource_title" => resource_title,
                      "institution_name" => institution,
                      "repository_name" => repository,
                      "series_id" => series_id,
                      "series_display" => series_display,
                      })
        end
      end
    end
    
    # replace the indicator with the subcontainer indicator
    # do this for convenience so we don't need to add another key to the config
    subcontainer_labels.each do |sl|
      sl["indicator"] = sl["sc_indicator"]
    end
    
    return subcontainer_labels
  end
  
  private
  
  # returns an agent name if a creator exists for the colelction linked to the top container
  def agent_for_top_container(tc)
    agent_names = []
    # resolve the linked agents
    URIResolver.resolve_references(tc['collection'],['linked_agents'])
    #find the first creator and set the name if there is one
    if tc['collection'].length > 0 && !tc['collection'][0].dig('_resolved','linked_agents').nil?
      agent_ref = tc['collection'][0]['_resolved']['linked_agents'].select{|a| a['role'] == 'creator'}
      agent_ref.each do |agent|
        agent_names << agent['_resolved']['title']
      end
      
      agent_name = agent_names.compact.join("; ")
    end
    
    agent_name
  end
  
    # returns a location and location barcode for a top container
  def location_for_top_container(tc)

    tc_loc = tc['container_locations'].select { |cl| cl['status'] == 'current' }.first
    loc = tc_loc ? tc_loc['_resolved'] : {}
    area = loc['area'] ? loc['area'] : ''
    location = ['coordinate_1_indicator', 'coordinate_2_indicator', 'coordinate_3_indicator'].map {|fld| loc[fld]}.compact.join(' ')
    location_barcode = loc['barcode'] ? loc['barcode'] : ''

    return area, location, location_barcode        
  end
  
  # returns two semicolon concatenated lists of all resource title and resource ids inked to the top container
  def resource_for_top_container(tc)
    resource_ids = []
    resource_titles = []
    
    resources = tc['collection'].empty? ? {} : tc['collection']
    resources.each do |res|
      resource_ids << res['identifier']
      resource_titles << res['display_string']
    end
    resource_id = resource_ids.compact.join("; ")
    resource_title = resource_titles.compact.join("; ")

    return resource_id, resource_title
  end
  
  # returns 2 semicolon concatenated strings: IDs and  display
  def series_for_top_container(tc)
    series_ids = []
    series_displays = []
    series = tc['series'].empty? ? {} : tc['series']
    series.each do |ser|
      series_ids << romanize_series_id(ser['identifier'])
      series_displays << ser['display_string']
    end
    series_id = series_ids.compact.join(@delim)
    if series_ids.length == 1
      series_id = @tag + series_id
    end
    series_display = series_displays.compact.join(@delim)
    return series_id, series_display
  end


  def institution_repo_for_top_container(tc)
    institution =  tc['repository']['_resolved']['parent_institution_name'] ? tc['repository']['_resolved']['parent_institution_name'] : ''
    repository = tc['repository']['_resolved']['name']
    
    return institution, repository
  end
  
  def load_top_containers(ids)
    top_container_list = TopContainer.filter(:id => ids).all
    top_container_json_records = Hash[TopContainer.sequel_to_jsonmodel(top_container_list).map {|tc| [tc.id, tc.to_hash(:trusted)]}]

    @top_container_json_records = URIResolver.resolve_references(top_container_json_records, ['container_locations','repository','collection'])
  end

  def fetch_top_container(id)
    @top_container_json_records.fetch(id)
  end
  
  # Returns a hash like {123 => {"ao_di" => 456, "level" => File, ...}, ...}, meaning "Top Container 123 links to Archival Object 456 with level_id 789, etc"
  def calculate_top_container_linkages(ids)
    result = {}

    TopContainer.linked_instance_ds.
      join(:archival_object, :id => :instance__archival_object_id).
      filter(:top_container__id => ids).
      select(Sequel.as(:archival_object__id, :ao_id),
             Sequel.as(:archival_object__level_id, :level),
             Sequel.as(:archival_object__title, :ao_title),
             Sequel.as(:sub_container__type_2_id, :type2),
             Sequel.as(:sub_container__indicator_2, :indicator2),
             Sequel.as(:sub_container__type_3_id, :type3),
             Sequel.as(:sub_container__indicator_3, :indicator3),
             Sequel.as(:top_container__id, :top_container_id)).each do |row|

      result[row[:top_container_id]] ||= []
      result[row[:top_container_id]] << {"ao_id" => row[:ao_id],
                                         "ao_title" => row[:ao_title],
                                         "level" => row[:level].nil? ? nil : EnumerationValue.filter(:enumeration_value__id => row[:level]).get(:value),
                                         "type2" => row[:type2].nil? ? nil : EnumerationValue.filter(:enumeration_value__id => row[:type2]).get(:value),
                                         "indicator2" => row[:indicator2],
                                         "type3" => row[:type3].nil? ? nil : EnumerationValue.filter(:enumeration_value__id => row[:type3]).get(:value),
                                         "indicator3" => row[:indicator3]
                                         }
    end

    result
  end
  
  class Romanizer
    extend RomanizeSeriesIdentifier
  end

end
