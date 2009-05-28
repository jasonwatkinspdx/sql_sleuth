module SqlSleuth
  MS_THRESHOLD    = 500.0   # If a query took longer than this, log the backtrace
  ROWS_THRESHOLD  = 200   # If a query returns more rows than this, log the backtrace
  
  RELEVANT_ENTITIES = [ 'app/models/', 'app/controllers/' ]
  RELEVANT_ENTITIES_EXP = Regexp.new(RELEVANT_ENTITIES.map do |e|
    "(?:#{Regexp.escape(File.join(RAILS_ROOT, e))})"
  end.join("|") + '(.*)')

end

class ActiveRecord::ConnectionAdapters::AbstractAdapter
  
  def log_with_sql_sleuth sql, name
    # gross, but not as gross as copy pasting the log method body
    t0 = Time.now.to_f
    result = log_without_sql_sleuth(sql, name){ yield if block_given? }
    ms = (Time.now.to_f - t0) * 1000
    
    rows = result.num_rows if result and result.respond_to? :num_rows
    log_info sql, name, ms, rows
    result
  end
  alias_method_chain :log, :sql_sleuth
  
  def log_info_with_sql_sleuth sql, name, ms, rows=0
    if ms.to_f > SqlSleuth::MS_THRESHOLD or rows.to_i > SqlSleuth::ROWS_THRESHOLD
      Rails.logger.info ['SQL SLEUTH:', "rows: #{rows}", ("db time: %.1fms" % [ms]), "source files:", sql_sleuth_backtrace, "sql:", sql].join(' ')
      notify_hoptoad :sql => sql, :name => name, :db_time => ms, :rows => rows, :backtrace => sql_sleuth_backtrace
    else
      log_info_without_sql_sleuth sql, name, ms
    end 
  end
  alias_method_chain :log_info, :sql_sleuth
  
  # returns a string of relevant source files from back trace, if any, otherwise an empty string
  def sql_sleuth_backtrace
    Kernel.caller.map{ |l| SqlSleuth::RELEVANT_ENTITIES_EXP.match(l) }.compact.map{ |m| m[1] }.compact.join(',')
  end
  
  def notify_hoptoad params
    HoptoadNotifier.notify :error_class => 'Sql Sleuth', :error_message => 'Badly behaving query', :backtrace => params[:backtrace], :request => params if defined? HoptoadNotifier
  end
  
end
