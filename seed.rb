# Redmine Seeding Script for NetOps Finance Mailer Integration
# Run with: bin/rails runner /seed.rb

puts "=== Initializing Redmine for NetOps Finance Mailer ==="

# 1. Enable REST API & Settings
puts "[1/7] Configuring Redmine Settings..."
Setting.rest_api_enabled = '1'
Setting.app_title = 'Redmine'
Setting.host_name = 'localhost:3005'
Setting.protocol = 'http'
Setting.jsonp_enabled = '0'
Setting.password_min_length = '4'
Setting.password_required_char_classes = []

# Load default configuration data if not already present
unless Tracker.exists?(id: 1) && IssueStatus.exists?(id: 1)
  puts "Loading Redmine default configuration data..."
  Redmine::DefaultData::Loader.load('en') rescue nil
end

# 2. Configure Issue Statuses
puts "[2/7] Configuring Issue Statuses..."
statuses = {
  1 => { name: "New", is_closed: false },
  2 => { name: "In Progress", is_closed: false },
  3 => { name: "Resolved", is_closed: false },
  4 => { name: "Feedback", is_closed: false },
  5 => { name: "Closed", is_closed: true },
  6 => { name: "Rejected", is_closed: true }
}

statuses.each do |id, data|
  status = IssueStatus.find_by(id: id) || IssueStatus.new
  status.id = id
  status.name = data[:name]
  status.is_closed = data[:is_closed]
  status.position = id
  status.save!
end

# 3. Configure Tracker 12: "License Request"
puts "[3/7] Configuring Tracker 12 (License Request)..."
tracker = Tracker.find_by(id: 12) || Tracker.new
tracker.id = 12
tracker.name = 'License Request'
tracker.default_status_id = 2
tracker.position = 4
tracker.is_in_roadmap = false
tracker.save!

# Ensure workflows for Tracker 12 across roles (Manager: 3, Developer: 4, Reporter: 5)
roles = Role.where(id: [3, 4, 5])
statuses.keys.each do |old_id|
  statuses.keys.each do |new_id|
    next if old_id == new_id
    roles.each do |r|
      WorkflowTransition.find_or_create_by!(
        tracker_id: 12,
        role_id: r.id,
        old_status_id: old_id,
        new_status_id: new_id
      )
    end
  end
end

# 4. Configure Custom Fields (IDs 1-9) matching Finance Mailer
puts "[4/7] Configuring Custom Fields..."
cfs_data = [
  { id: 1, name: 'Business Line', field_format: 'list', possible_values: ['Buy', 'Sell', 'Corporate', 'Internal'] },
  { id: 2, name: 'Name of the License', field_format: 'string' },
  { id: 3, name: 'Purpose', field_format: 'text' },
  { id: 4, name: 'Name of the Project', field_format: 'string' },
  { id: 5, name: 'Duration', field_format: 'string' },
  { id: 6, name: 'BL Head/Project Manager', field_format: 'string' },
  { id: 7, name: 'Approved', field_format: 'list', possible_values: ['No', 'Yes'], default_value: 'No' },
  { id: 8, name: 'Billing Type', field_format: 'list', possible_values: ['Cost to Business Line', 'Cost to Project', 'Overhead'] },
  { id: 9, name: 'Finance Notified', field_format: 'bool', default_value: '0' }
]

cfs_data.each do |d|
  cf = IssueCustomField.find_by(id: d[:id]) || IssueCustomField.new
  cf.id = d[:id]
  cf.name = d[:name]
  cf.field_format = d[:field_format]
  cf.possible_values = d[:possible_values] if d[:possible_values]
  cf.default_value = d[:default_value] if d[:default_value]
  cf.is_for_all = true
  cf.is_filter = true
  cf.trackers = Tracker.where(id: [1, 2, 3, 12])
  cf.save!
end

# 5. Configure Users & API Keys
puts "[5/7] Configuring Users and API Tokens..."
admin_pass = ENV['REDMINE_ADMIN_PASSWORD'].presence || 'AdminPassword123!'
api_user_pass = ENV['REDMINE_API_PASSWORD'].presence || 'ApiServicePassword123!'
api_key = ENV['REDMINE_API_KEY'].presence || 'fedcba9876543210fedcba9876543210fedcba98'
admin_api_key = ENV['ADMIN_API_KEY'].presence || '9f8e7d6c5b4a3928170f1e2d3c4b5a69788796a5'

# Admin user (ID 1)
admin = User.find_by(id: 1) || User.find_by(login: 'admin')
if admin
  admin.password = admin_pass
  admin.password_confirmation = admin_pass
  admin.must_change_passwd = false
  admin.save(validate: false)
  token_admin = Token.find_by(user_id: admin.id, action: 'api') || Token.new(user_id: admin.id, action: 'api')
  token_admin.save(validate: false)
  token_admin.update_columns(value: admin_api_key)
end

users_seed = [
  { id: 10, login: 'sweetlin', mail: 'sweetlin.p@tarento.com', firstname: 'Sweetlin', lastname: 'Panjikaran', admin: false },
  { id: 20, login: 'vishwanath', mail: 'vishwanath.a@tarento.com', firstname: 'Vishwanath', lastname: 'Ashi', admin: false },
  { id: 30, login: 'imran', mail: 'imran.u@tarento.com', firstname: 'Imran', lastname: 'Ulla', admin: false },
  { id: 40, login: 'api-service', mail: 'api-service@tarento.com', firstname: 'API', lastname: 'Service', admin: true }
]

users_seed.each do |ud|
  u = User.find_by(id: ud[:id]) || User.find_by(login: ud[:login]) || User.new
  u.id = ud[:id]
  u.login = ud[:login]
  u.mail = ud[:mail]
  u.firstname = ud[:firstname]
  u.lastname = ud[:lastname]
  u.admin = ud[:admin]
  u.status = 1
  u.password = (ud[:login] == 'api-service' ? api_user_pass : 'Password123!')
  u.password_confirmation = u.password
  u.must_change_passwd = false
  u.save!

  if ud[:login] == 'api-service'
    t = Token.find_by(user_id: u.id, action: 'api') || Token.new(user_id: u.id, action: 'api')
    t.save(validate: false)
    t.update_columns(value: api_key)
  end
end

# 6. Configure Project 1: NetOps Support
puts "[6/7] Configuring Project 1 (NetOps Support)..."
proj = Project.find_by(id: 1) || Project.find_by(identifier: 'netops-support') || Project.new
proj.id = 1
proj.name = 'NetOps Support'
proj.identifier = 'netops-support'
proj.description = 'NetOps Support and License Requests'
proj.is_public = true
proj.trackers = Tracker.where(id: [1, 2, 3, 12])
proj.enabled_module_names = ['issue_tracking']
proj.save!

manager_role = Role.find_by(id: 3) || Role.first
[1, 10, 20, 30, 40].each do |uid|
  u = User.find(uid)
  m = Member.find_by(project_id: proj.id, user_id: u.id) || Member.new(project: proj, user: u)
  m.roles = [manager_role]
  m.save!
end

# 7. Seed Test Tickets (23593, 23594, 23595)
puts "[7/7] Seeding Test Issues (23593, 23594, 23595)..."

common_cfs = {
  1 => 'Buy',
  2 => 'Claude',
  3 => 'Heineken Report Generation',
  4 => 'Heineken',
  5 => '3 months',
  6 => 'Imran Ulla',
  8 => 'Cost to Business Line',
  9 => '0'
}

# --- Ticket 23593: Approved, valid approval history ---
t23593 = Issue.find_by(id: 23593) || Issue.new
t23593.id = 23593
t23593.project = proj
t23593.tracker_id = 12
t23593.status_id = 2
t23593.author_id = 10
t23593.priority_id = 2
t23593.subject = 'Request for Claude Subscription'
t23593.description = 'Need Claude Team for 3 users.'
t23593.created_on = Time.parse('2026-11-13T09:00:00Z')
t23593.updated_on = Time.parse('2026-11-14T08:00:00Z')
t23593.save!(validate: false)

cfs_23593 = common_cfs.merge(7 => 'Yes')
cfs_23593.each do |cf_id, val|
  cv = CustomValue.find_or_initialize_by(customized_type: 'Issue', customized_id: t23593.id, custom_field_id: cf_id)
  cv.value = val
  cv.save!
end

t23593.journals.destroy_all

j1 = t23593.journals.build(
  user_id: 20,
  created_on: Time.parse('2026-11-13T10:00:00Z'),
  notes: 'Kindly obtain approval from @Imran Baig'
)
j1.save!

j2 = t23593.journals.build(
  user_id: 30,
  created_on: Time.parse('2026-11-14T07:00:00Z'),
  notes: 'Approved.'
)
j2.save!
jd2 = j2.details.build(
  property: 'cf',
  prop_key: '7',
  old_value: 'No',
  value: 'Yes'
)
jd2.save!

t23593.attachments.destroy_all
att = t23593.attachments.build(
  author_id: 10,
  filename: 'claude_subscription_quote.pdf',
  description: 'Anthropic Claude Team quote for 3 users',
  content_type: 'application/pdf',
  created_on: Time.parse('2026-11-13T09:05:00Z')
)
att.file = StringIO.new('%PDF-1.4 Mock Claude Subscription Quote Content')
att.save!

# --- Ticket 23594: Self-approved ---
t23594 = Issue.find_by(id: 23594) || Issue.new
t23594.id = 23594
t23594.project = proj
t23594.tracker_id = 12
t23594.status_id = 2
t23594.author_id = 10
t23594.priority_id = 2
t23594.subject = 'Request for Claude Subscription'
t23594.description = 'Need Claude Team for 3 users.'
t23594.created_on = Time.parse('2026-11-13T09:00:00Z')
t23594.updated_on = Time.parse('2026-11-14T08:00:00Z')
t23594.save!(validate: false)

cfs_23594 = common_cfs.merge(7 => 'Yes')
cfs_23594.each do |cf_id, val|
  cv = CustomValue.find_or_initialize_by(customized_type: 'Issue', customized_id: t23594.id, custom_field_id: cf_id)
  cv.value = val
  cv.save!
end

t23594.journals.destroy_all
j_self = t23594.journals.build(
  user_id: 10,
  created_on: Time.parse('2026-11-14T07:30:00Z'),
  notes: ''
)
j_self.save!
jd_self = j_self.details.build(
  property: 'cf',
  prop_key: '7',
  old_value: 'No',
  value: 'Yes'
)
jd_self.save!

# --- Ticket 23595: Not approved ---
t23595 = Issue.find_by(id: 23595) || Issue.new
t23595.id = 23595
t23595.project = proj
t23595.tracker_id = 12
t23595.status_id = 2
t23595.author_id = 10
t23595.priority_id = 2
t23595.subject = 'Request for Claude Subscription'
t23595.description = 'Need Claude Team for 3 users.'
t23595.created_on = Time.parse('2026-11-13T09:00:00Z')
t23595.updated_on = Time.parse('2026-11-14T08:00:00Z')
t23595.save!(validate: false)

cfs_23595 = common_cfs.merge(7 => 'No')
cfs_23595.each do |cf_id, val|
  cv = CustomValue.find_or_initialize_by(customized_type: 'Issue', customized_id: t23595.id, custom_field_id: cf_id)
  cv.value = val
  cv.save!
end
t23595.journals.destroy_all

# Reset PostgreSQL sequences so new records don't collide
ActiveRecord::Base.connection.tables.each do |table|
  sequence = "#{table}_id_seq"
  seq_exists = ActiveRecord::Base.connection.select_value("SELECT to_regclass('#{sequence}')")
  if seq_exists
    max_id = ActiveRecord::Base.connection.select_value("SELECT MAX(id) FROM #{table}").to_i
    if max_id > 0
      ActiveRecord::Base.connection.execute("SELECT setval('#{sequence}', #{max_id})")
    end
  end
end

puts "=== Redmine Initialization and Seeding Completed Successfully! ==="
