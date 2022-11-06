variable "ami-name" {
  type    = string
  default = ""
}

variable "ami-prefix" {
  type    = string
  default = "depot-machine-github-actions"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  runner_version = "2.299.1"

  name = var.ami-name == "" ? "${var.ami-prefix}-${local.timestamp}" : var.ami-name
}

locals {
  dockerhub_login = ""
  dockerhub_password = ""
  helper_script_folder ="/imagegeneration/helpers"
  image_folder = "/imagegeneration"
  image_os = "ubuntu20"
  image_version = "20221027.1"
  imagedata_file = "/imagegeneration/imagedata.json"
  installer_script_folder = "/imagegeneration/installers"
  run_validation_diskspace = "false"
  template_dir = "${path.root}/generated"
}

packer {
  required_plugins {
    amazon = {
      version = "1.1.1"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "amd64" {
  ami_name              = var.ami-name == "" ? "${var.ami-prefix}-amd64-${local.timestamp}" : "${var.ami-name}-amd64"
  instance_type         = "c6i.large"
  region                = "us-east-1"
  ssh_username          = "ubuntu"
  force_deregister      = true
  force_delete_snapshot = true
  // ami_groups            = ["all"]

  // # Copy to all non-opt-in regions (in addition to us-east-1 above)
  // # See: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html
  // ami_regions = [
  //   "ap-northeast-1",
  //   "ap-northeast-2",
  //   "ap-northeast-3",
  //   "ap-south-1",
  //   "ap-southeast-1",
  //   "ap-southeast-2",
  //   "ca-central-1",
  //   "eu-central-1",
  //   "eu-north-1",
  //   "eu-west-1",
  //   "eu-west-2",
  //   "eu-west-3",
  //   "sa-east-1",
  //   "us-east-2",
  //   "us-west-1",
  //   "us-west-2",
  // ]

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
      architecture        = "x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 86
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Wait up to an hour for the AMI to be ready.
  aws_polling {
    delay_seconds = 15
    max_attempts  = 240
  }
}

build {
  name    = "amd64"
  sources = ["source.amazon-ebs.amd64"]

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = ["mkdir ${local.image_folder}", "chmod 777 ${local.image_folder}"]
  }

  provisioner "shell" {
    script          = "${local.template_dir}/scripts/base/apt-mock.sh"
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    scripts          = ["${local.template_dir}/scripts/base/repos.sh"]
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    script           = "${local.template_dir}/scripts/base/apt.sh"
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    script          = "${local.template_dir}/scripts/base/limits.sh"
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "file" {
    source      = "${local.template_dir}/scripts/helpers"
    destination = "${local.helper_script_folder}"
  }

  provisioner "file" {
    source      = "${local.template_dir}/scripts/installers"
    destination = "${local.installer_script_folder}"
  }

  provisioner "file" {
    source      = "${local.template_dir}/post-generation"
    destination = "${local.image_folder}"
  }

  provisioner "file" {
    source      = "${local.template_dir}/scripts/tests"
    destination = "${local.image_folder}"
  }

  provisioner "file" {
    source      = "${local.template_dir}/scripts/SoftwareReport"
    destination = "${local.image_folder}"
  }

  provisioner "file" {
    source      = "${local.template_dir}/toolsets/toolset-2004.json"
    destination = "${local.installer_script_folder}/toolset.json"
  }

  provisioner "shell" {
    scripts = ["${local.template_dir}/scripts/installers/preimagedata.sh"]
    environment_vars = [
      "IMAGE_VERSION=${local.image_version}",
      "IMAGEDATA_FILE=${local.imagedata_file}"
    ]
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    scripts = ["${local.template_dir}/scripts/installers/configure-environment.sh"]
    environment_vars = [
      "IMAGE_VERSION=${local.image_version}",
      "IMAGE_OS=${local.image_os}",
      "HELPER_SCRIPTS=${local.helper_script_folder}"
    ]
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    scripts = [
      "${local.template_dir}/scripts/installers/complete-snap-setup.sh",
      "${local.template_dir}/scripts/installers/powershellcore.sh"
    ]
    environment_vars = ["HELPER_SCRIPTS=${local.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    scripts = [
      "${local.template_dir}/scripts/installers/Install-PowerShellModules.ps1",
      "${local.template_dir}/scripts/installers/Install-AzureModules.ps1"
    ]
    environment_vars = [
      "HELPER_SCRIPTS=${local.helper_script_folder}",
      "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}"
    ]
    execute_command = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
  }

  provisioner "shell" {
    scripts = [
      "${local.template_dir}/scripts/installers/docker-compose.sh",
      "${local.template_dir}/scripts/installers/docker-moby.sh"
    ]
    environment_vars = [
      "HELPER_SCRIPTS=${local.helper_script_folder}",
      "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}",
      "DOCKERHUB_LOGIN=${local.dockerhub_login}",
      "DOCKERHUB_PASSWORD=${local.dockerhub_password}"
    ]
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    scripts = [
      "${local.template_dir}/scripts/installers/azcopy.sh",
      "${local.template_dir}/scripts/installers/azure-cli.sh",
      "${local.template_dir}/scripts/installers/azure-devops-cli.sh",
      "${local.template_dir}/scripts/installers/basic.sh",
      "${local.template_dir}/scripts/installers/bicep.sh",
      "${local.template_dir}/scripts/installers/aliyun-cli.sh",
      "${local.template_dir}/scripts/installers/apache.sh",
      "${local.template_dir}/scripts/installers/aws.sh",
      "${local.template_dir}/scripts/installers/clang.sh",
      "${local.template_dir}/scripts/installers/swift.sh",
      "${local.template_dir}/scripts/installers/cmake.sh",
      "${local.template_dir}/scripts/installers/codeql-bundle.sh",
      "${local.template_dir}/scripts/installers/containers.sh",
      "${local.template_dir}/scripts/installers/dotnetcore-sdk.sh",
      "${local.template_dir}/scripts/installers/erlang.sh",
      "${local.template_dir}/scripts/installers/firefox.sh",
      "${local.template_dir}/scripts/installers/microsoft-edge.sh",
      "${local.template_dir}/scripts/installers/gcc.sh",
      "${local.template_dir}/scripts/installers/gfortran.sh",
      "${local.template_dir}/scripts/installers/git.sh",
      "${local.template_dir}/scripts/installers/github-cli.sh",
      "${local.template_dir}/scripts/installers/google-chrome.sh",
      "${local.template_dir}/scripts/installers/google-cloud-sdk.sh",
      "${local.template_dir}/scripts/installers/haskell.sh",
      "${local.template_dir}/scripts/installers/heroku.sh",
      "${local.template_dir}/scripts/installers/hhvm.sh",
      "${local.template_dir}/scripts/installers/java-tools.sh",
      "${local.template_dir}/scripts/installers/kubernetes-tools.sh",
      "${local.template_dir}/scripts/installers/oc.sh",
      "${local.template_dir}/scripts/installers/leiningen.sh",
      "${local.template_dir}/scripts/installers/miniconda.sh",
      "${local.template_dir}/scripts/installers/mono.sh",
      "${local.template_dir}/scripts/installers/kotlin.sh",
      "${local.template_dir}/scripts/installers/mysql.sh",
      "${local.template_dir}/scripts/installers/mssql-cmd-tools.sh",
      "${local.template_dir}/scripts/installers/sqlpackage.sh",
      "${local.template_dir}/scripts/installers/nginx.sh",
      "${local.template_dir}/scripts/installers/nvm.sh",
      "${local.template_dir}/scripts/installers/nodejs.sh",
      "${local.template_dir}/scripts/installers/bazel.sh",
      "${local.template_dir}/scripts/installers/oras-cli.sh",
      "${local.template_dir}/scripts/installers/phantomjs.sh",
      "${local.template_dir}/scripts/installers/php.sh",
      "${local.template_dir}/scripts/installers/postgresql.sh",
      "${local.template_dir}/scripts/installers/pulumi.sh",
      "${local.template_dir}/scripts/installers/ruby.sh",
      "${local.template_dir}/scripts/installers/r.sh",
      "${local.template_dir}/scripts/installers/rust.sh",
      "${local.template_dir}/scripts/installers/julia.sh",
      "${local.template_dir}/scripts/installers/sbt.sh",
      "${local.template_dir}/scripts/installers/selenium.sh",
      "${local.template_dir}/scripts/installers/terraform.sh",
      "${local.template_dir}/scripts/installers/packer.sh",
      "${local.template_dir}/scripts/installers/vcpkg.sh",
      "${local.template_dir}/scripts/installers/dpkg-config.sh",
      "${local.template_dir}/scripts/installers/mongodb.sh",
      "${local.template_dir}/scripts/installers/yq.sh",
      "${local.template_dir}/scripts/installers/android.sh",
      "${local.template_dir}/scripts/installers/pypy.sh",
      "${local.template_dir}/scripts/installers/python.sh",
      "${local.template_dir}/scripts/installers/graalvm.sh"
    ]
    environment_vars = [
      "HELPER_SCRIPTS=${local.helper_script_folder}",
      "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}",
      "DEBIAN_FRONTEND=noninteractive"
    ]
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    scripts = [
      "${local.template_dir}/scripts/installers/Install-Toolset.ps1",
      "${local.template_dir}/scripts/installers/Configure-Toolset.ps1"
    ]
    environment_vars = [
      "HELPER_SCRIPTS=${local.helper_script_folder}",
      "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}"
    ]
    execute_command = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
  }

  provisioner "shell" {
    scripts = ["${local.template_dir}/scripts/installers/pipx-packages.sh"]
    environment_vars = [
      "HELPER_SCRIPTS=${local.helper_script_folder}",
      "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}"
    ]
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    scripts = ["${local.template_dir}/scripts/installers/homebrew.sh"]
    environment_vars = [
      "HELPER_SCRIPTS=${local.helper_script_folder}",
      "DEBIAN_FRONTEND=noninteractive",
      "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}"
    ]
    execute_command = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    script          = "${local.template_dir}/scripts/base/snap.sh"
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    expect_disconnect = true
    scripts           = ["${local.template_dir}/scripts/base/reboot.sh"]
    execute_command   = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    pause_before        = "60s"
    start_retry_timeout = "10m"
    scripts             = ["${local.template_dir}/scripts/installers/cleanup.sh"]
    execute_command     = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    script          = "${local.template_dir}/scripts/base/apt-mock-remove.sh"
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  // provisioner "shell" {
  //   max_retries         = 3
  //   start_retry_timeout = "2m"
  //   inline = [
  //     "pwsh -Command Write-Host Running SoftwareReport.Generator.ps1 script",
  //     "pwsh -File ${local.image_folder}/SoftwareReport/SoftwareReport.Generator.ps1 -OutputDirectory ${local.image_folder}",
  //     "pwsh -Command Write-Host Running RunAll-Tests.ps1 script",
  //     "pwsh -File ${local.image_folder}/tests/RunAll-Tests.ps1 -OutputDirectory ${local.image_folder}"
  //   ]
  //   environment_vars = [
  //     "IMAGE_VERSION=${local.image_version}",
  //     "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}"
  //   ]
  // }

  // provisioner "file" {
  //   source      = "${local.image_folder}/Ubuntu-Readme.md"
  //   destination = "${local.template_dir}/Ubuntu2004-Readme.md"
  //   direction   = "download"
  // }

  provisioner "shell" {
    scripts = ["${local.template_dir}/scripts/installers/post-deployment.sh"]
    environment_vars = [
      "HELPER_SCRIPT_FOLDER=${local.helper_script_folder}",
      "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}",
      "IMAGE_FOLDER=${local.image_folder}"
    ]
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  # Depot-specific provisioning
  provisioner "shell" {
    scripts = ["${path.root}/scripts/provision-user.sh"]
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }
  provisioner "shell" {
    scripts = ["${path.root}/scripts/install-runner.sh"]
    environment_vars = ["RUNNER_VERSION=${local.runner_version}"]
    execute_command = "sudo -u runner sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    scripts          = ["${local.template_dir}/scripts/installers/validate-disk-space.sh"]
    environment_vars = ["RUN_VALIDATION=${local.run_validation_diskspace}"]
  }

  provisioner "file" {
    source      = "${local.template_dir}/config/ubuntu2004.conf"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /etc/vsts",
      "cp /tmp/ubuntu2004.conf /etc/vsts/machine_instance.conf"
    ]
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    inline = [
      "sleep 30",
      "userdel -fr ubuntu || echo \"Suppressing userdel exit $?\"",
      "groupdel ubuntu || echo \"Suppressing groupdel exit $?\"",
      "export HISTSIZE=0 && sync"
    ]
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }
}

// source "amazon-ebs" "arm64" {
//   ami_name              = var.ami-name == "" ? "${var.ami-prefix}-arm64-${local.timestamp}" : "${var.ami-name}-arm64"
//   instance_type         = "c6g.large"
//   region                = "us-east-1"
//   ssh_username          = "ec2-user"
//   force_deregister      = true
//   force_delete_snapshot = true
//   ami_groups            = ["all"]

//   # Copy to all non-opt-in regions (in addition to us-east-1 above)
//   # See: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html
//   ami_regions = [
//     "ap-northeast-1",
//     "ap-northeast-2",
//     "ap-northeast-3",
//     "ap-south-1",
//     "ap-southeast-1",
//     "ap-southeast-2",
//     "ca-central-1",
//     "eu-central-1",
//     "eu-north-1",
//     "eu-west-1",
//     "eu-west-2",
//     "eu-west-3",
//     "sa-east-1",
//     "us-east-2",
//     "us-west-1",
//     "us-west-2",
//   ]

//   source_ami_filter {
//     filters = {
//       name                = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-*"
//       architecture        = "arm64"
//       root-device-type    = "ebs"
//       virtualization-type = "hvm"
//     }
//     most_recent = true
//     owners      = ["099720109477"] # Canonical
//   }

//   launch_block_device_mappings {
//     device_name           = "/dev/sda1"
//     volume_size           = 10
//     volume_type           = "gp3"
//     delete_on_termination = true
//   }

//   # Wait up to an hour for the AMI to be ready.
//   aws_polling {
//     delay_seconds = 15
//     max_attempts  = 240
//   }
// }

// build {
//   name    = "arm64"
//   sources = ["source.amazon-ebs.arm64"]

//   provisioner "shell" {
//     execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
//     script          = "${local.template_dir}/provision.sh"
//   }
// }
