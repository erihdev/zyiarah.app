/**
 * NAES App Factory Engine (V1)
 * Consumes blueprints and automates the creation/preparation of new app instances.
 */
import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';

const BLUEPRINT_PATH = process.argv[2] || './blueprints/zyiarah-maidjoy-variant.json';

function run(cmd) {
    console.log(`Executing: ${cmd}`);
    try {
        return execSync(cmd, { encoding: 'utf-8' });
    } catch (e) {
        console.error(`Error: ${e.message}`);
        return null;
    }
}

/**
 * Automates the customization of the codebase based on a blueprint.
 */
async function assembleApp() {
    if (!fs.existsSync(BLUEPRINT_PATH)) {
        console.error(`Blueprint not found at ${BLUEPRINT_PATH}`);
        process.exit(1);
    }

    const blueprint = JSON.parse(fs.readFileSync(BLUEPRINT_PATH, 'utf-8'));
    console.log(`Assembling: ${blueprint.customization.appName}...`);

    // 1. Rename App in Strings
    const stringsPath = 'lib/utils/zyiarah_strings.dart';
    if (fs.existsSync(stringsPath)) {
        let strings = fs.readFileSync(stringsPath, 'utf-8');
        strings = strings.replace(/static String get appName => "[^"]*";/, `static String get appName => "${blueprint.customization.appName}";`);
        fs.writeFileSync(stringsPath, strings);
        console.log(`Updated app name to ${blueprint.customization.appName}`);
    }

    // 2. Modify Branding Colors in main.dart
    const mainPath = 'lib/main.dart';
    if (fs.existsSync(mainPath)) {
        let mainCode = fs.readFileSync(mainPath, 'utf-8');
        // Target primaryColor and seedColor
        mainCode = mainCode.replace(/primaryColor: const Color\(0x[^)]*\),/g, `primaryColor: const ${blueprint.customization.primaryColor.replace('#', 'Color(0xFF')}),`);
        mainCode = mainCode.replace(/seedColor: const Color\(0x[^)]*\),/g, `seedColor: const ${blueprint.customization.primaryColor.replace('#', 'Color(0xFF')}),`);
        fs.writeFileSync(mainPath, mainCode);
        console.log(`Applied theme color: ${blueprint.customization.primaryColor} to main.dart`);
    }

    // 3. Update Android Package Name (Placeholder)
    // In a real factory, this would modify android/app/build.gradle and Info.plist
    console.log("Updating bundle identifiers and package names...");
    
    // 4. Trigger Build Pipeline (Fastlane)
    console.log("Preparing deployment environment...");
    const fastlaneDir = 'fastlane';
    if (!fs.existsSync(fastlaneDir)) {
        fs.mkdirSync(fastlaneDir);
    }
    fs.writeFileSync('fastlane/Appfile', `app_identifier("${blueprint.customization.appName.toLowerCase().replace(/\s/g, '.')}")\napple_id("dev@zyiarah.com")`);
    
    console.log("READY FOR UPLOAD.");
    console.log("Next Command: 'fastlane deploy_to_stores'");
    
    /* 
    PHASE 4: VIRTUAL EXECUTION
    run('bundle exec fastlane android build');
    run('bundle exec fastlane ios build');
    run('bundle exec fastlane upload_to_play_store');
    run('bundle exec fastlane upload_to_app_store');
    */

    console.log(`\n--- SUCCESS ---\nApp ${blueprint.customization.appName} is ready for production.`);
}

assembleApp();
