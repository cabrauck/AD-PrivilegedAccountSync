# 🛡️ Protected Users Group Sync for Active Directory

This PowerShell script automatically synchronizes privileged users into the **"Protected Users"** group in Active Directory based on specific criteria.

---

## ⚠️ Notes

Using the **Protected Users** group is a powerful security measure to harden privileged accounts against modern attack techniques:

* 🛡️ It disables legacy authentication methods such as NTLM and weak Kerberos delegation.
* 🔒 It ensures credentials are not cached on devices, reducing lateral movement risks.
* 📉 Greatly reduces the attack surface of high-value accounts like Domain Admins.

> ℹ️ Always test in a lab environment before deploying in production.

---

## 🔧 Features

* ✅ Adds users with `AdminCount = 1` to the **Protected Users** group
* ✅ Adds users who are members of any of the following privileged groups:

  * Domain Admins
  * Enterprise Admins
  * Schema Admins
  * Administrators
  * Backup Operators
  * Server Operators
  * Account Operators
* ✅ Removes users from **Protected Users** group who no longer meet any of the above criteria
* 📄 Generates a log file with all actions taken
* 📁 Archives the previous log on every run

---

## 📂 Log Output

* Log directory: `C:\Logs`
* Current run: `ProtectedUsersSync.log`
* Archived logs: `ProtectedUsersSync_yyyy-MM-dd_HH-mm-ss.log`
* Final line in each log includes a summary: e.g.

  ```text
  2025-05-05 03:00:00	Script execution completed. 3 users added, 1 user removed from Protected Users group.
  ```

---

## 🚀 Usage

### 1. Requirements

* PowerShell on a Domain Controller
* ActiveDirectory PowerShell module
* Sufficient permissions to modify group memberships (Domain Admin or delegated rights)

### 2. Manual Execution

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Path\To\ProtectedUsersSync.ps1"
```

### 3. Scheduled Task Setup 🕒

To run this script automatically every day:

* Open **Task Scheduler**
* Create a new task:

  **General Tab:**

  * Name: `Protected Users Sync`
  * Run with highest privileges
  * Configure for: `Windows Server`

  **Trigger Tab:**

  * Daily at `03:00 AM`

  **Action Tab:**

  * Program/script: `powershell.exe`
  * Add arguments:

    ```
    -ExecutionPolicy Bypass -File "C:\Path\To\ProtectedUsersSync.ps1"
    ```

  **Conditions & Settings:**

  * Configure as needed (e.g., run only if connected to domain)

---

## 📜 License

MIT License – use freely with attribution.

---

## ✨ Contributions Welcome!

Feel free to fork and contribute. Issues and PRs are appreciated. 💡

---

## 🧠 Author

Built and maintained with 🧠 + 💻 by \[YourNameHere]
