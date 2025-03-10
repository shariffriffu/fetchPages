library fetch_pages;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:json_dynamic_widget/json_dynamic_widget.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FetchPages {
  static final logger = Logger();
  static var responseData;
  static Future<void> fetchPagesFromAPI(String url, String appVersion) async {
    try {
      final SharedPreferences pref = await SharedPreferences.getInstance();
      final localVersionConfig = pref.getString("versionConfig");
      bool shouldFetchPages = false;
      logger.i("Url: $url :: appVersion: $appVersion");

      // Fetch versionMapping.json from the server with appVersion to get JSON version and dirName
      logger.i("Version Mapping URL :: $url/version-mapping/$appVersion");
      final versionResponse =
          await http.get(Uri.parse("$url/version-mapping/$appVersion"));
      pref.setString("versionConfig",
          versionResponse.body); // Update the versionConfig in sharedPrefs
          
      if (localVersionConfig != null) {
        final localVersionData = json.decode(localVersionConfig);
        logger.i("Local versionConfig found.");
        if (versionResponse.statusCode == 200) {
          final serverVersionData = json.decode(versionResponse.body);
          final localVersion = localVersionData['version'];
          final serverVersion = serverVersionData['version'];
          logger.i(
              "Local version: $localVersion, Server version: $serverVersion");

          // Compare versions
          if (localVersion != serverVersion) {
            logger.i("Local version is outdated. Fetching pages...");
            shouldFetchPages = true;
          } else {
            logger.i("Versions match. No need to fetch pages.");
          }
        } else {
          logger.e(
              "Error fetching versionConfig from server: ${versionResponse.body}");
        }
      } else {
        logger.i("No local versionConfig found. Fetching pages...");
        shouldFetchPages = true;
      }

      // Fetch pages only if necessary
      if (shouldFetchPages) {
        final localVersionConfig = pref.getString("versionConfig");
        final localVersionData = json.decode(localVersionConfig!);
        String folderName = localVersionData['folderName'];
        logger.i("Fetch pages URL :: $url/pages/$folderName");
        final response = await http.get(Uri.parse("$url/pages/$folderName"));
        if (response.statusCode == 200) {
          responseData = json.decode(response.body);
          pref.setString("responseBody", response.body);
          logger.i("Fetched pages from API successfully!");
        } else if (pref.getString('responseBody') != null) {
          responseData = json.decode(pref.getString('responseBody')!);
          logger.w(
              "Error fetching pages from API, loaded from sharedPreferences");
        } else {
          logger.e("Error fetching page data from API ${response.body}");
        }
      } else {
        logger.i("Else if not to fetch pages");
        responseData = json.decode(pref.getString('responseBody')!);
      }
    } catch (e) {
      logger.e("Exception while fetching pages from API: $e");
    }
  }

  static Future<String?> getPageByName(String name) async {
    if (responseData != null && responseData[name] != null) {
      logger.i("Fetched $name successfully!");
      return json.encode(responseData[name]);
    }
    logger.e("Could not load the page requested: $name");
    return null;
  }
}

class RenderPage extends StatefulWidget {
  final Map<String, dynamic> pageData;
  final JsonWidgetRegistry registry;
  const RenderPage({Key? key, required this.pageData, required this.registry}) : super(key: key);

  @override
  RenderPageState createState() => RenderPageState();
}

class RenderPageState extends State<RenderPage> {
  Map<dynamic, dynamic> mapData = {};
  Logger logger = Logger();
  Future<void> _readJSON() async {
    try {
      final String? pageData =
          await FetchPages.getPageByName(widget.pageData['pageName']);
      if (pageData != null) {
        final data = json.decode(pageData);
        logger.i("Fetched page data for ${widget.pageData['pageName']}");
        setState(() {
          mapData = data;
        });
      } else {
        logger.e(
            "ReadJSON: page data is null for ${widget.pageData['pageName']}");
      }
    } catch (e) {
      logger.e("ReadJSON: could not read page data: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.pageData['data'] != null) {
      Map<String, dynamic> dataKeyValue = widget.pageData['data'];
      dataKeyValue.forEach((key, value) {
        widget.registry.setValue(key, value);
      });
    }
    _readJSON();
  }

  @override
  Widget build(BuildContext context) {
    if (mapData.isEmpty) {
      return Dialog(
        backgroundColor: Colors.transparent, // Make the dialog transparent
        child: Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Color.fromARGB(0, 255, 255, 255),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                    Color.fromRGBO(0, 43, 124, 1)), // Set color to orange
              ),
            ),
          ),
        ),
      );
    } else {
      try {
        var widgetData =
            JsonWidgetData.fromDynamic(mapData, registry: widget.registry);
        return widgetData.build(context: context);
      } catch (e) {
        logger.e("Error building widget: $e");
        return const Center(
          child: Text('Error loading page'),
        );
      }
    }
  }
}
