import requests
import os
import json
from bs4 import BeautifulSoup
from datetime import datetime
from zoneinfo import ZoneInfo

def promiedos() -> dict:
    """
        Scrapes a website and extracts various elements.
        
        Parameters:
        url (str): The URL of the website to scrape.
        
        Returns:
        dict: A dictionary containing the extracted elements.
    """
    # Send a GET request to the URL
    response = requests.get('https://www.promiedos.com.ar')

    # Parse the HTML content using Beautiful Soup
    soup = BeautifulSoup(response.content, "html.parser")

    # get leagues
    leagues = soup.find_all(id="fixturein")

    games_results = {}
    
    for league in leagues:
        league_results = []

        # title
        league_title_html = league.find('tr', {"class": 'tituloin'})
        league_title = league_title_html.find('a').text.strip()
        print(league_title)

        # get games per league
        games = league.find_all('tr', {"name":["nvp", "vp"]})
        
        for game in games:
            # print(game)

            ## times
            time = ''
            # if not started
            game_time = game.find('td', {"class": 'game-time'})
            if game_time:
                time = game_time.text.strip()
            
            # if playing
            game_play = game.find('td', {"class": 'game-play'})
            if game_play:
                time = game_play.text.strip()
            
            # if ended
            game_fin = game.find('td', {"class": 'game-fin'})
            if game_fin:
                time = game_fin.text.strip()

            ## teams
            # results
            result_local = game.find('td', {"class": 'game-r1'})
            if result_local:
                result_local = result_local.text.strip()
            
            result_visitor = game.find('td', {"class": 'game-r2'})
            if result_visitor:
                result_visitor = result_visitor.text.strip()

            # teams
            teams = game.find_all('td', {"class": 'game-t1'})
            if len(teams) > 0:
                team_local = teams[0].text.strip()
                team_visitor = teams[1].text.strip()

                if ':' in time:
                    formatted_time = datetime.combine(datetime.today(), datetime.strptime(time, '%H:%M').time(), ZoneInfo('America/Argentina/Buenos_Aires')).isoformat()
                else:
                    formatted_time = time

                league_results.append({
                    'local': { 'team': team_local, 'result': result_local },
                    'visitor': { 'team': team_visitor, 'result': result_visitor },
                    'time': formatted_time
                })
                
                print(f"- Time: {time} [Argentina] | {team_local} ({result_local}) Vs. {team_visitor} ({result_visitor})")
            
        games_results[league_title] = league_results

    return games_results

def lambda_handler(event, context):
    promiedos_response = promiedos()

    send_telegram_message(promiedos_response)

    return promiedos_response

def send_telegram_message(response):
    try:
        bot_request = 'https://api.telegram.org/bot' + os.environ['TELEGRAM_TOKEN'] + '/sendMessage?chat_id=' + os.environ['TELEGRAM_CHAT_ID'] + '&text=' + json.dumps(response)
        print(bot_request)
        return requests.get(bot_request) 
    except Exception as e:
        print(f"Error: {e}")