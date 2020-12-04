# active-directory-domain-join-boshrelease

## Requirements

* vSphere with existing bosh director
* Windows 2019 stemcell including packages sources for `AD-Domain-Services` and `DNS` uploaded to director

## Usage
Build and deploy
```
pushd active-directory-domain-join-boshrelease
  bosh create-release && bosh upload-release
popd

bosh deploy -d gmsa manifest.yml 
```

manifest.yml
```
name: ((deployment_name))
releases:
- name: "windows-utilities"
  version: "0.8.0"
  url: "https://bosh.io/d/github.com/cloudfoundry-incubator/windows-utilities-release?v=0.8.0"
  sha1: "110cbc7b177ec66dec4ba7d2e567d2ecadd04053"
- name: "windows-tools"
  version: "54"
  url: "https://bosh.io/d/github.com/cloudfoundry-incubator/windows-tools-release?v=54"
  sha1: "d82a8f4664091c26d425859cc20b0dcccfc2cd64"
- name: "active-directory-domain-join"
  version: latest
instance_groups:
- name: domain-controllers
  lifecycle: service
  networks:
  - name: default
    static_ips: [((domain_controller_ip_address))]
  stemcell: windows
  vm_type: windows
  azs:
  - z1
  instances: 1
  jobs:
  - name: promote-domain-controller
    release: active-directory-domain-join
    properties:
      domain_fqdn: ((domain_fqdn))
      domain_admin_username: ((domain_admin_username))
      domain_admin_password: ((domain_admin_password))
      run_after_reboot_ps1: 'c:\var\vcap\jobs\create-gmsa\bin\run.ps1'
  - name: create-gmsa
    release: active-directory-domain-join
    properties:
      domain_fqdn: ((domain_fqdn))
      domain_admin_username: ((domain_admin_username))
      domain_admin_password: ((domain_admin_password))
      domain_user_username: ((domain_user_username))
      domain_user_password: ((domain_user_password))
      domain_group_name: ((domain_group_name))
      domain_service_account_name: ((domain_service_account_name))
  - name: enable_ssh
    release: windows-utilities
  - name: set_password
    release: windows-utilities
    properties:
      set_password:
        password: ((local_admin_password))
- name: domain-vms
  lifecycle: service
  networks:
  - name: default
  stemcell: windows
  vm_type: windows
  azs:
  - z1
  instances: 6
  persistent_disk: 20480
  jobs:
  - name: setup-persistent-disk-store
    release: windows-tools
    properties: { disk_number: 2 }
  - name: enable_ssh
    release: windows-utilities
  - name: docker
    release: windows-tools
    properties:
      docker: { use_persistent_disk_store: true }
  - name: set_password
    release: windows-utilities
    properties:
      set_password:
        password: ((local_admin_password))
  - name: join-domain
    release: active-directory-domain-join
    properties:
      domain_fqdn: ((domain_fqdn))
      domain_controller_ip_address: ((domain_controller_ip_address))
      domain_user_username: ((domain_user_username))
      domain_user_password: ((domain_user_password))
  - name: join-gmsa
    release: active-directory-domain-join
    properties:
      domain_fqdn: ((domain_fqdn))
      domain_user_username: ((domain_user_username))
      domain_user_password: ((domain_user_password))
      domain_group_name: ((domain_group_name))
      domain_service_account_name: ((domain_service_account_name))
  - name: smoke-tests
    release: active-directory-domain-join
    properties:
      domain_fqdn: ((domain_fqdn))
      domain_service_account_name: ((domain_service_account_name))
stemcells:
- alias: windows
  os: windows2019
  version: 2019.7
update:
  canaries: 2
  canary_watch_time: 1000-30000
  max_in_flight: 2
  update_watch_time: 1000-30000
  serial: false
```


## Tags
* Team: Windows Containers
* Product: PASW, PKS Windows Workers
* Coding Language(s): bosh-release, Powershell
* Subject Area: Windows, Active Directory
