/**
      This file is part of Adguard for iOS (https://github.com/AdguardTeam/AdguardForiOS).
      Copyright © Adguard Software Limited. All rights reserved.

      Adguard for iOS is free software: you can redistribute it and/or modify
      it under the terms of the GNU General Public License as published by
      the Free Software Foundation, either version 3 of the License, or
      (at your option) any later version.

      Adguard for iOS is distributed in the hope that it will be useful,
      but WITHOUT ANY WARRANTY; without even the implied warranty of
      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
      GNU General Public License for more details.

      You should have received a copy of the GNU General Public License
      along with Adguard for iOS.  If not, see <http://www.gnu.org/licenses/>.
*/


import UIKit

class AdvancedSettingsController: UITableViewController {

    @IBOutlet weak var useSimplifiedFiltersSwitch: UISwitch!
    @IBOutlet weak var showStatusbarSwitch: UISwitch!
    @IBOutlet weak var restartProtectionSwitch: UISwitch!
    @IBOutlet weak var tunnelModeDescription: ThemableLabel!
    @IBOutlet weak var lastSeparator: UIView!
    
    @IBOutlet var themableLabels: [ThemableLabel]!
    @IBOutlet var separators: [UIView]!
    
    private let theme: ThemeServiceProtocol = ServiceLocator.shared.getService()!
    private let resources: AESharedResourcesProtocol = ServiceLocator.shared.getService()!
    private let safariService: SafariService = ServiceLocator.shared.getService()!
    private let filterService: FiltersServiceProtocol = ServiceLocator.shared.getService()!
    private let antibanner: AESAntibannerProtocol = ServiceLocator.shared.getService()!
    private let vpnManager: VpnManagerProtocol = ServiceLocator.shared.getService()!
    private let contentBlockerService: ContentBlockerService = ServiceLocator.shared.getService()!
    private let configuration: ConfigurationService = ServiceLocator.shared.getService()!
    
    private let segueIdentifier = "contentBlockersScreen"
    
    private let useSimplifiedRow = 0
    private let showStatusbarRow = 1
    private let restartProtectionRow = 2
    private let removeVpnProfile = 5
    
    private var themeObservation: NotificationToken?
    private var vpnConfigurationObserver: NotificationToken?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        updateTheme()
        setupBackButton()
        
        useSimplifiedFiltersSwitch.isOn = resources.sharedDefaults().bool(forKey: AEDefaultsJSONConverterOptimize)
        restartProtectionSwitch.isOn = resources.restartByReachability
        showStatusbarSwitch.isOn = configuration.showStatusBar
        
        themeObservation = NotificationCenter.default.observe(name: NSNotification.Name( ConfigurationService.themeChangeNotification), object: nil, queue: OperationQueue.main) {[weak self] (notification) in
            self?.updateTheme()
        }
        
        vpnConfigurationObserver = NotificationCenter.default.observe(name: ComplexProtectionService.systemProtectionChangeNotification, object: nil, queue: .main) { [weak self] (note) in
            self?.lastSeparator.isHidden = false
            self?.tableView.reloadData()
        }
        
        setTunnelModeDescription()
    }
    
    // MARK: - Prepare for segue
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == segueIdentifier{
            let contentBlockersDataSource = ContentBlockersDataSource(safariService: safariService, resources: resources, filterService: filterService, antibanner: antibanner)
            let destinationVC = segue.destination as? ContentBlockerStateController
            destinationVC?.contentBlockersDataSource = contentBlockersDataSource
            destinationVC?.theme = theme
        }
    }
    
    // MARK: - actions
    
    @IBAction func useSimplifiedFiltersAction(_ sender: UISwitch) {
        change(senderSwitch: sender, forKey: AEDefaultsJSONConverterOptimize)
    }
    
    @IBAction func showProgressbarAction(_ sender: UISwitch) {
        if !sender.isOn {
           NotificationCenter.default.post(name: NSNotification.Name.HideStatusView, object: self)
        }
        configuration.showStatusBar = sender.isOn
    }
    
    @IBAction func restartProtectionAction(_ sender: UISwitch) {
        resources.restartByReachability = sender.isOn
        vpnManager.updateSettings(completion: nil)
    }
    
    // MARK: - Table view data source
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        cell.isHidden = false
        
        if indexPath.row == restartProtectionRow && !configuration.proStatus{
            cell.isHidden = true
        }
        
        if indexPath.row == removeVpnProfile && !vpnManager.vpnInstalled {
            cell.isHidden = true
        }
        
        theme.setupTableCell(cell)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.row {
        case useSimplifiedRow:
            useSimplifiedFiltersSwitch.setOn(!useSimplifiedFiltersSwitch.isOn, animated: true)
            useSimplifiedFiltersAction(useSimplifiedFiltersSwitch)
        case showStatusbarRow:
            showStatusbarSwitch.setOn(!showStatusbarSwitch.isOn, animated: true)
            showProgressbarAction(showStatusbarSwitch)
        case restartProtectionRow:
            restartProtectionSwitch.setOn(!restartProtectionSwitch.isOn, animated: true)
            restartProtectionAction(restartProtectionSwitch)
        case removeVpnProfile:
            showRemoveVpnAlert(indexPath)
        default:
            break
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        if indexPath.row == restartProtectionRow && !configuration.proStatus{
            return 0.0
        }
        
        if indexPath.row == removeVpnProfile && !vpnManager.vpnInstalled {
            lastSeparator.isHidden = true
            return 0.0
        }
        
        return super.tableView(tableView, heightForRowAt: indexPath)
    }
    
    // MARK: - Private methods
    
    private func change(senderSwitch: UISwitch, forKey key: String) {
        let backgroundTaskId = UIApplication.shared.beginBackgroundTask { }
        
        let oldValue = resources.sharedDefaults().bool(forKey: key)
        let newValue = senderSwitch.isOn
        
        if oldValue != newValue {
            resources.sharedDefaults().set(newValue, forKey: key)
            
            contentBlockerService.reloadJsons(backgroundUpdate: false) { [weak self] (error) in
                if error != nil {
                    self?.resources.sharedDefaults().set(oldValue, forKey: key)
                    DispatchQueue.main.async {
                        senderSwitch.setOn(oldValue, animated: true)
                    }
                }
                UIApplication.shared.endBackgroundTask(backgroundTaskId)
            }
        }
    }
    
    private func updateTheme() {
        view.backgroundColor = theme.backgroundColor
        theme.setupLabels(themableLabels)
        theme.setupNavigationBar(navigationController?.navigationBar)
        theme.setupTable(tableView)
        theme.setupSeparators(separators)
        theme.setupSwitch(useSimplifiedFiltersSwitch)
        theme.setupSwitch(showStatusbarSwitch)
        theme.setupSwitch(restartProtectionSwitch)

        DispatchQueue.main.async { [weak self] in
            guard let sSelf = self else { return }
            sSelf.tableView.reloadData()
        }
    }
    
    private func setTunnelModeDescription() {
        switch resources.tunnelMode {
        case APVpnManagerTunnelModeSplit:
            tunnelModeDescription.text = String.localizedString("tunnel_mode_split_description")
        case APVpnManagerTunnelModeFull:
            tunnelModeDescription.text = String.localizedString("tunnel_mode_full_description")
        case APVpnManagerTunnelModeFullWithoutVPNIcon:
            tunnelModeDescription.text = String.localizedString("tunnel_mode_full_without_icon_description")
        default:
            break
        }
    }
    
    private func showRemoveVpnAlert(_ indexPath: IndexPath) {
        let alert = UIAlertController(title: String.localizedString("remove_vpn_profile_title"), message: String.localizedString("remove_vpn_profile_message"), preferredStyle: .actionSheet)
        
        let removeAction = UIAlertAction(title: String.localizedString("remove_title").uppercased(), style: .destructive) {[weak self] _ in
            guard let self = self else { return }
            self.vpnManager.removeVpnConfiguration {(error) in
                DispatchQueue.main.async {
                    DDLogInfo("AdvancedSettingsController - removing VPN profile")
                    if error != nil {
                        ACSSystemUtils.showSimpleAlert(for: self, withTitle: String.localizedString("remove_vpn_profile_error_title"), message: String.localizedString("remove_vpn_profile_error_message"))
                        DDLogError("AdvancedSettingsController - error removing VPN profile")
                    }
                }
            }
        }
        
        alert.addAction(removeAction)
        
        let cancelAction = UIAlertAction(title: String.localizedString("common_action_cancel"), style: .cancel) { _ in
        }
        
        alert.addAction(cancelAction)
        
        if let presenter = alert.popoverPresentationController, let cell = tableView.cellForRow(at: indexPath) {
            presenter.sourceView = cell
            presenter.sourceRect = cell.bounds
        }

        self.present(alert, animated: true)
    }

}
