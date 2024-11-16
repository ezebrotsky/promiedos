import requests
import os
import json

from bs4 import BeautifulSoup
from datetime import datetime
from zoneinfo import ZoneInfo
from dotenv import load_dotenv

load_dotenv()

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

    formatted_response = format_matches(promiedos_response)
    send_telegram_message(formatted_response)

    return promiedos_response

def send_telegram_message(message):
    try:
        bot_request = 'https://api.telegram.org/bot' + os.getenv('TELEGRAM_TOKEN') + '/sendMessage?chat_id=' + os.getenv('TELEGRAM_CHAT_ID') + '&parse_mode=html&text=' + message

        return requests.get(bot_request) 
    except Exception as e:
        print(f"Error: {e}")

def format_matches(json_data):
    """
    Format football matches JSON data in a readable way.
    
    Args:
        json_data (str or dict): JSON string or dictionary containing matches data
        
    Returns:
        str: Formatted string with matches information
    """
    # If input is a string, parse it to dictionary
    if isinstance(json_data, str):
        data = json.loads(json_data)
    else:
        data = json_data
        
    formatted_output = []
    
    for tournament, matches in data.items():
        # Add tournament header
        formatted_output.append(f"<b>\U0001F3C6 {tournament}</b>")
        
        # Process each match
        for match in matches:
            # Parse and format the time
            try:
                match_time = datetime.fromisoformat(match['time'])
                israeli_time = match_time.astimezone(ZoneInfo('Asia/Jerusalem'))
                formatted_time = israeli_time.strftime("%H:%M")
                formatted_date = israeli_time.strftime("%d/%m")
            except Exception:
                formatted_date = "LIVE"
                formatted_date = match["time"]

            
            # Format match details
            local_team = match['local']['team']
            visitor_team = match['visitor']['team']
            local_result = match['local']['result'] or '-'
            visitor_result = match['visitor']['result'] or '-'
            
            # Create match line with aligned teams and scores
            match_line = (
                f"\U000023F0 {formatted_date} {formatted_time} | \U000026BD "
                f"{local_team} [{local_result}] vs "
                f"[{visitor_result}] {visitor_team}"
            )
            
            formatted_output.append(match_line)
        
        # Add empty line between tournaments
        formatted_output.append('%0A')
    
    return '%0A%0A'.join(formatted_output)


if __name__ == '__main__':
    lambda_handler({},{})